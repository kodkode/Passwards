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

    /// One round trip: send a message, await the single reply.
    func roundTrip(_ message: BrowserWireMessage) async throws -> BrowserWireMessage {
        try await send(message)
        return try await receive()
    }
}

@Suite("Browser bridge server", .serialized)
struct BrowserBridgeServerTests {

    private func tempSocketPath() -> String {
        // Unix socket paths cap at ~104 bytes; keep it short.
        "/tmp/2pw-test-\(UInt32.random(in: 0..<UInt32.max)).sock"
    }

    private func makeServer(_ app: FakeAppSide) async throws -> (BrowserBridgeServer, String) {
        let path = tempSocketPath()
        let server = BrowserBridgeServer(socketPath: path, delegate: app, pairings: app)
        try await server.start()
        try await Task.sleep(for: .milliseconds(200))
        return (server, path)
    }

    /// Drive the pairing handshake to a verdict, polling like the JS does.
    private func pair(
        client: FakeExtensionClient, expectConfirmed: Bool
    ) async throws -> (staticKey: Curve25519.KeyAgreement.PrivateKey, staticPub: Data, secret: SymmetricKey, code: String) {
        let cid = UUID().uuidString
        let staticKey = Curve25519.KeyAgreement.PrivateKey()
        let staticPub = staticKey.publicKey.rawRepresentation

        let response = try await client.roundTrip(
            BrowserWireMessage(type: .pairRequest, cid: cid, publicKey: staticPub.base64EncodedString()))
        #expect(response.type == .pairResponse)
        let appPub = Data(base64Encoded: response.publicKey!)!
        let (secret, code) = try BrowserChannelCrypto.pairing(
            myPrivateKey: staticKey, peerPublicKey: appPub,
            extensionPublicKey: staticPub, appPublicKey: appPub)

        // Poll until the app's async approval resolves.
        for _ in 0..<50 {
            let verdict = try await client.roundTrip(BrowserWireMessage(type: .pairPoll, cid: cid))
            if verdict.type == .pairPending { try await Task.sleep(for: .milliseconds(50)); continue }
            #expect(verdict.type == (expectConfirmed ? .pairConfirmed : .pairRejected))
            return (staticKey, staticPub, secret, code)
        }
        Issue.record("pairing never resolved")
        return (staticKey, staticPub, secret, code)
    }

    /// Open a session over `client` for `cid`, returning the derived keys.
    private func startSession(
        client: FakeExtensionClient, cid: String,
        staticPub: Data, secret: SymmetricKey
    ) async throws -> (extToApp: SymmetricKey, appToExt: SymmetricKey) {
        let eph = Curve25519.KeyAgreement.PrivateKey()
        let ephPub = eph.publicKey.rawRepresentation
        let accept = try await client.roundTrip(BrowserWireMessage(
            type: .sessionStart, cid: cid,
            publicKey: staticPub.base64EncodedString(),
            ephemeralKey: ephPub.base64EncodedString()))
        #expect(accept.type == .sessionAccept)
        let appEph = Data(base64Encoded: accept.ephemeralKey!)!
        let keys = try BrowserChannelCrypto.sessionKeys(
            myEphemeral: eph, peerEphemeralPublicKey: appEph, pairingSecret: secret,
            extensionEphemeralPublicKey: ephPub, appEphemeralPublicKey: appEph)
        return (keys.extensionToApp, keys.appToExtension)
    }

    @Test func pairThenSessionThenRPC() async throws {
        let app = FakeAppSide()
        let (server, path) = try await makeServer(app)
        defer { Task { await server.stop() } }

        let client = FakeExtensionClient(socketPath: path)
        let paired = try await pair(client: client, expectConfirmed: true)
        #expect(app.lock.withLock { app.approvedCodes } == [paired.code])

        // Session over a new connection (like a browser restart).
        let cid = UUID().uuidString
        let client2 = FakeExtensionClient(socketPath: path)
        let keys = try await startSession(
            client: client2, cid: cid, staticPub: paired.staticPub, secret: paired.secret)

        // RPCs.
        let query = BrowserRequest(id: 1, method: .credentialsQuery, url: "https://github.com/login")
        let reply1 = try BrowserChannelCrypto.open(
            try await client2.roundTrip(try BrowserChannelCrypto.seal(
                JSONEncoder().encode(query), role: .extensionSide, seq: 0, key: keys.extToApp).with(cid: cid)),
            from: .app, expectedSeq: 0, key: keys.appToExt)
        #expect(try JSONDecoder().decode(BrowserResponse.self, from: reply1).matches?.first?.title == "GitHub")

        let fill = BrowserRequest(id: 2, method: .credentialsFill, url: "https://github.com/login", itemID: "item-1")
        let reply2 = try BrowserChannelCrypto.open(
            try await client2.roundTrip(try BrowserChannelCrypto.seal(
                JSONEncoder().encode(fill), role: .extensionSide, seq: 1, key: keys.extToApp).with(cid: cid)),
            from: .app, expectedSeq: 1, key: keys.appToExt)
        #expect(try JSONDecoder().decode(BrowserResponse.self, from: reply2).password == "hunter2")
    }

    @Test func sessionResumesAcrossReconnect() async throws {
        // The whole point of cid-keying: Safari's relay can drop and reopen the
        // socket mid-session, so a NEW socket carrying the same cid must keep
        // the sequence counters running rather than reset them.
        let app = FakeAppSide()
        let (server, path) = try await makeServer(app)
        defer { Task { await server.stop() } }

        let client = FakeExtensionClient(socketPath: path)
        let paired = try await pair(client: client, expectConfirmed: true)

        let cid = UUID().uuidString
        let connA = FakeExtensionClient(socketPath: path)
        let keys = try await startSession(
            client: connA, cid: cid, staticPub: paired.staticPub, secret: paired.secret)

        // First RPC on connection A (seq 0).
        let q0 = BrowserRequest(id: 1, method: .status)
        let r0 = try BrowserChannelCrypto.open(
            try await connA.roundTrip(try BrowserChannelCrypto.seal(
                JSONEncoder().encode(q0), role: .extensionSide, seq: 0, key: keys.extToApp).with(cid: cid)),
            from: .app, expectedSeq: 0, key: keys.appToExt)
        #expect(try JSONDecoder().decode(BrowserResponse.self, from: r0).locked == false)

        // Reconnect: brand-new socket, SAME cid + SAME keys, next seq (1).
        let connB = FakeExtensionClient(socketPath: path)
        let q1 = BrowserRequest(id: 2, method: .credentialsFill, itemID: "item-1")
        let r1 = try BrowserChannelCrypto.open(
            try await connB.roundTrip(try BrowserChannelCrypto.seal(
                JSONEncoder().encode(q1), role: .extensionSide, seq: 1, key: keys.extToApp).with(cid: cid)),
            from: .app, expectedSeq: 1, key: keys.appToExt)
        #expect(try JSONDecoder().decode(BrowserResponse.self, from: r1).password == "hunter2")
    }

    @Test func sessionEndDropsSession() async throws {
        let app = FakeAppSide()
        let (server, path) = try await makeServer(app)
        defer { Task { await server.stop() } }

        let client = FakeExtensionClient(socketPath: path)
        let paired = try await pair(client: client, expectConfirmed: true)

        let cid = UUID().uuidString
        let conn = FakeExtensionClient(socketPath: path)
        let keys = try await startSession(
            client: conn, cid: cid, staticPub: paired.staticPub, secret: paired.secret)

        _ = try await conn.roundTrip(BrowserWireMessage(type: .sessionEnd, cid: cid))

        // After session-end the cid is gone: an enc must be refused, not served.
        let q = BrowserRequest(id: 1, method: .status)
        let reply = try await conn.roundTrip(try BrowserChannelCrypto.seal(
            JSONEncoder().encode(q), role: .extensionSide, seq: 0, key: keys.extToApp).with(cid: cid))
        #expect(reply.type == .error)
    }

    @Test func unpairedSessionIsRefused() async throws {
        let app = FakeAppSide()
        let (server, path) = try await makeServer(app)
        defer { Task { await server.stop() } }

        let client = FakeExtensionClient(socketPath: path)
        let eph = Curve25519.KeyAgreement.PrivateKey()
        let reply = try await client.roundTrip(BrowserWireMessage(
            type: .sessionStart, cid: UUID().uuidString,
            publicKey: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation.base64EncodedString(),
            ephemeralKey: eph.publicKey.rawRepresentation.base64EncodedString()))
        #expect(reply.type == .error)
        #expect(reply.message == "not paired")
    }

    @Test func rejectedPairingIsNotStored() async throws {
        let app = FakeAppSide()
        app.approve = false
        let (server, path) = try await makeServer(app)
        defer { Task { await server.stop() } }

        let client = FakeExtensionClient(socketPath: path)
        _ = try await pair(client: client, expectConfirmed: false)
        #expect(app.lock.withLock { app.pairings.isEmpty })
    }
}

private extension BrowserWireMessage {
    /// Stamp the connection id onto a sealed envelope (seal() doesn't know it).
    func with(cid: String) -> BrowserWireMessage {
        var copy = self
        copy.cid = cid
        return copy
    }
}
