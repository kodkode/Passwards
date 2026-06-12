import Foundation
import Testing
import CryptoKit
import Network
@testable import TwoPasswordCore

/// Fake app side: approves every pairing, remembers it, serves canned RPCs.
private final class FakeAppSide: BrowserBridgeDelegate, BrowserPairingStore, @unchecked Sendable {
    let lock = NSLock()
    var pairings: [Data: Data] = [:]
    var approvedCodes: [String] = []
    var approve = true

    func approveBrowserPairing(verificationCode: String) async -> Bool {
        lock.withLock { approvedCodes.append(verificationCode) }
        return lock.withLock { approve }
    }

    func handleBrowserRequest(_ request: BrowserRequest) async -> BrowserResponse {
        switch request.method {
        case .status:
            return BrowserResponse(id: request.id, locked: false)
        case .credentialsQuery:
            return BrowserResponse(id: request.id, matches: [
                .init(itemID: "item-1", title: "GitHub", username: "michael"),
            ])
        case .credentialsFill:
            return BrowserResponse(id: request.id, username: "michael", password: "hunter2")
        case .loginSave:
            return BrowserResponse(id: request.id, savedItemID: "item-2")
        case .fillPending:
            return BrowserResponse(id: request.id, username: "michael", password: "hunter2", submit: true)
        }
    }

    func pairingSecret(forExtensionKey key: Data) async -> Data? {
        lock.withLock { pairings[key] }
    }

    func savePairing(extensionKey: Data, secret: Data) async {
        lock.withLock { pairings[extensionKey] = secret }
    }
}

/// Minimal extension-side client speaking the wire protocol over the socket,
/// the same way the JS background worker will.
private final class FakeExtensionClient: @unchecked Sendable {
    let connection: NWConnection
    var buffer = Data()
    var pending: [BrowserWireMessage] = []

    init(socketPath: String) {
        connection = NWConnection(to: .unix(path: socketPath), using: .tcp)
        connection.start(queue: DispatchQueue(label: "fake-extension"))
    }

    func send(_ message: BrowserWireMessage) async throws {
        let data = try NativeMessageFraming.encodeMessage(message)
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { c.resume(throwing: error) } else { c.resume() }
            })
        }
    }

    func receive() async throws -> BrowserWireMessage {
        while true {
            if !pending.isEmpty { return pending.removeFirst() }
            let chunk: Data = try await withCheckedThrowingContinuation { c in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                    if let error { c.resume(throwing: error) }
                    else if let data, !data.isEmpty { c.resume(returning: data) }
                    else if isComplete { c.resume(throwing: BrowserChannelCrypto.ChannelError.decryptFailed) }
                    else { c.resume(returning: Data()) }
                }
            }
            buffer += chunk
            for frame in try NativeMessageFraming.drainFrames(from: &buffer) {
                pending.append(try NativeMessageFraming.decodeMessage(frame))
            }
        }
    }
}

@Suite("Browser bridge server", .serialized)
struct BrowserBridgeServerTests {

    private func tempSocketPath() -> String {
        // Unix socket paths cap at ~104 bytes; keep it short.
        "/tmp/2pw-test-\(UInt32.random(in: 0..<UInt32.max)).sock"
    }

    @Test func pairThenSessionThenRPC() async throws {
        let app = FakeAppSide()
        let path = tempSocketPath()
        let server = BrowserBridgeServer(socketPath: path, delegate: app, pairings: app)
        try await server.start()
        defer { Task { await server.stop() } }
        try await Task.sleep(for: .milliseconds(200))

        // --- Pair ---
        let staticKey = Curve25519.KeyAgreement.PrivateKey()
        let staticPub = staticKey.publicKey.rawRepresentation
        let client = FakeExtensionClient(socketPath: path)
        try await client.send(BrowserWireMessage(type: .pairRequest, publicKey: staticPub.base64EncodedString()))

        let pairResponse = try await client.receive()
        #expect(pairResponse.type == .pairResponse)
        let appPub = Data(base64Encoded: pairResponse.publicKey!)!
        let (pairingSecret, code) = try BrowserChannelCrypto.pairing(
            myPrivateKey: staticKey, peerPublicKey: appPub,
            extensionPublicKey: staticPub, appPublicKey: appPub)

        let confirmed = try await client.receive()
        #expect(confirmed.type == .pairConfirmed)
        #expect(app.lock.withLock { app.approvedCodes } == [code])

        // --- Session (new connection, like a browser restart) ---
        let client2 = FakeExtensionClient(socketPath: path)
        let eph = Curve25519.KeyAgreement.PrivateKey()
        let ephPub = eph.publicKey.rawRepresentation
        try await client2.send(BrowserWireMessage(
            type: .sessionStart,
            publicKey: staticPub.base64EncodedString(),
            ephemeralKey: ephPub.base64EncodedString()))

        let accept = try await client2.receive()
        #expect(accept.type == .sessionAccept)
        let appEph = Data(base64Encoded: accept.ephemeralKey!)!
        let keys = try BrowserChannelCrypto.sessionKeys(
            myEphemeral: eph, peerEphemeralPublicKey: appEph, pairingSecret: pairingSecret,
            extensionEphemeralPublicKey: ephPub, appEphemeralPublicKey: appEph)

        // --- RPCs ---
        let query = BrowserRequest(id: 1, method: .credentialsQuery, url: "https://github.com/login")
        try await client2.send(try BrowserChannelCrypto.seal(
            JSONEncoder().encode(query), role: .extensionSide, seq: 0, key: keys.extensionToApp))
        let reply1 = try BrowserChannelCrypto.open(
            try await client2.receive(), from: .app, expectedSeq: 0, key: keys.appToExtension)
        let queryResponse = try JSONDecoder().decode(BrowserResponse.self, from: reply1)
        #expect(queryResponse.matches?.first?.title == "GitHub")

        let fill = BrowserRequest(id: 2, method: .credentialsFill, url: "https://github.com/login", itemID: "item-1")
        try await client2.send(try BrowserChannelCrypto.seal(
            JSONEncoder().encode(fill), role: .extensionSide, seq: 1, key: keys.extensionToApp))
        let reply2 = try BrowserChannelCrypto.open(
            try await client2.receive(), from: .app, expectedSeq: 1, key: keys.appToExtension)
        let fillResponse = try JSONDecoder().decode(BrowserResponse.self, from: reply2)
        #expect(fillResponse.password == "hunter2")
    }

    @Test func unpairedSessionIsRefused() async throws {
        let app = FakeAppSide()
        let path = tempSocketPath()
        let server = BrowserBridgeServer(socketPath: path, delegate: app, pairings: app)
        try await server.start()
        defer { Task { await server.stop() } }
        try await Task.sleep(for: .milliseconds(200))

        let client = FakeExtensionClient(socketPath: path)
        let eph = Curve25519.KeyAgreement.PrivateKey()
        try await client.send(BrowserWireMessage(
            type: .sessionStart,
            publicKey: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation.base64EncodedString(),
            ephemeralKey: eph.publicKey.rawRepresentation.base64EncodedString()))
        let reply = try await client.receive()
        #expect(reply.type == .error)
        #expect(reply.message == "not paired")
    }

    @Test func rejectedPairingIsNotStored() async throws {
        let app = FakeAppSide()
        app.approve = false
        let path = tempSocketPath()
        let server = BrowserBridgeServer(socketPath: path, delegate: app, pairings: app)
        try await server.start()
        defer { Task { await server.stop() } }
        try await Task.sleep(for: .milliseconds(200))

        let client = FakeExtensionClient(socketPath: path)
        let staticKey = Curve25519.KeyAgreement.PrivateKey()
        try await client.send(BrowserWireMessage(
            type: .pairRequest,
            publicKey: staticKey.publicKey.rawRepresentation.base64EncodedString()))
        _ = try await client.receive() // pair-response
        let verdict = try await client.receive()
        #expect(verdict.type == .pairRejected)
        #expect(app.lock.withLock { app.pairings.isEmpty })
    }
}
