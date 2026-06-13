import Foundation
import CryptoKit
import Network
import os

/// App-side callbacks the bridge needs. Implemented by the app target;
/// kept abstract here so the whole server is testable headless.
public protocol BrowserBridgeDelegate: Sendable {
    /// Show the verification code and ask the user to approve the new
    /// browser pairing. Return false to reject.
    func approveBrowserPairing(verificationCode: String) async -> Bool
    /// Serve one decrypted RPC. Implementations decide lock-state policy.
    func handleBrowserRequest(_ request: BrowserRequest) async -> BrowserResponse
}

/// Persistence for approved pairings (the app stores them in the Keychain).
public protocol BrowserPairingStore: Sendable {
    func pairingSecret(forExtensionKey key: Data) async -> Data?
    func savePairing(extensionKey: Data, secret: Data) async
}

/// Unix-socket server speaking the `BrowserWireMessage` protocol.
///
/// Session and pairing state are keyed by the extension's `cid`, not by socket
/// connection — so the same logical port resumes its sequence counters even if
/// the underlying socket is dropped and reopened. That's what lets Safari's
/// short-lived app-extension act as a stateless relay: it may reconnect between
/// any two messages, and the app simply continues the `cid`'s session. Chrome's
/// persistent host connection is just the degenerate case where one socket
/// carries the whole `cid` lifetime.
public actor BrowserBridgeServer {
    /// Both the app (server) and the Safari extension (client) must agree on
    /// this; on macOS an app-group id is Team-ID-prefixed.
    public static let appGroupIdentifier = "L5774582ZK.com.michael.twopassword"

    /// Lives in the shared App Group container so the sandboxed Safari
    /// app-extension can reach it too (a sandboxed process may only open a
    /// Unix socket inside a group container both sides are entitled for). The
    /// short filename keeps the path under the 104-byte `sockaddr_un` limit.
    public static func defaultSocketPath() -> String {
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return container.appendingPathComponent("2pw.sock").path
        }
        // Unentitled contexts (unit tests, command-line tooling): the group
        // container is unavailable, so fall back to the home directory.
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".2password-bridge.sock").path
    }

    /// Per-`cid` decrypted session, owned here (not in the transient socket).
    private struct Session {
        var extensionToApp: SymmetricKey
        var appToExtension: SymmetricKey
        var receiveSeq: UInt64
        var sendSeq: UInt64
        var lastSeen: Date
    }

    /// A pairing whose verification code the user is currently deciding on.
    /// The verdict is *pulled* by the extension via `pairPoll`, because Safari
    /// forbids the app pushing an unsolicited `pairConfirmed`.
    private struct PendingPairing {
        enum Verdict { case pending, confirmed, rejected }
        var secret: Data
        var extensionKey: Data
        var verdict: Verdict
        var createdAt: Date
    }

    private static let sessionTTL: TimeInterval = 600   // 10 min idle
    private static let pairingTTL: TimeInterval = 300   // 5 min to approve

    private let path: String
    private let delegate: BrowserBridgeDelegate
    private let pairings: BrowserPairingStore
    private var listener: NWListener?
    private var connectionTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var sessions: [String: Session] = [:]
    private var pendingPairings: [String: PendingPairing] = [:]

    public init(socketPath: String, delegate: BrowserBridgeDelegate, pairings: BrowserPairingStore) {
        self.path = socketPath
        self.delegate = delegate
        self.pairings = pairings
    }

    public func start() throws {
        guard listener == nil else { return }
        // The group container is provisioned lazily; make sure it exists so
        // bind() doesn't fail on a missing parent directory.
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        // A stale socket file from a previous run blocks bind.
        unlink(path)
        let parameters = NWParameters()
        parameters.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        parameters.requiredLocalEndpoint = NWEndpoint.unix(path: path)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { await self.adopt(connection) }
        }
        listener.stateUpdateHandler = { [path] state in
            switch state {
            case .ready:
                // Only this user may talk to the vault.
                chmod(path, 0o600)
            case .failed(let error):
                Logger(subsystem: "com.michael.twopassword", category: "browser-bridge")
                    .error("listener failed: \(error)")
            default:
                break
            }
        }
        listener.start(queue: DispatchQueue(label: "browser-bridge-listener"))
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        for task in connectionTasks.values { task.cancel() }
        connectionTasks.removeAll()
        sessions.removeAll()
        pendingPairings.removeAll()
        unlink(path)
    }

    private func adopt(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        let bridge = BridgeConnection(connection: connection, server: self)
        connectionTasks[id] = Task {
            await bridge.run()
            await self.forget(id)
        }
    }

    private func forget(_ id: ObjectIdentifier) {
        connectionTasks[id] = nil
    }

    // MARK: Dispatch (all state lives here, serialized by the actor)

    /// Handle one inbound wire message and return exactly one reply. One reply
    /// per inbound message is what keeps the protocol usable over Safari's
    /// per-message `beginRequest`/`completeRequest` relay.
    func handle(_ message: BrowserWireMessage) async -> BrowserWireMessage {
        switch message.type {
        case .pairRequest:  return await handlePairRequest(message)
        case .pairPoll:     return handlePairPoll(message.cid)
        case .sessionStart: return await handleSessionStart(message)
        case .sessionEnd:
            if let cid = message.cid { sessions[cid] = nil }
            return BrowserWireMessage(type: .sessionEnd, cid: message.cid)
        case .enc:          return await handleEnc(message)
        default:
            return BrowserWireMessage(type: .error, cid: message.cid, message: "protocol error")
        }
    }

    // MARK: Pairing (request → response, then poll for the user's verdict)

    private func handlePairRequest(_ message: BrowserWireMessage) async -> BrowserWireMessage {
        guard let cid = message.cid,
              let keyB64 = message.publicKey, let extensionKey = Data(base64Encoded: keyB64), extensionKey.count == 32 else {
            return BrowserWireMessage(type: .error, cid: message.cid, message: "invalid pairing request")
        }
        let appKeyPair = Curve25519.KeyAgreement.PrivateKey()
        let appPublic = appKeyPair.publicKey.rawRepresentation
        guard let (secret, code) = try? BrowserChannelCrypto.pairing(
            myPrivateKey: appKeyPair, peerPublicKey: extensionKey,
            extensionPublicKey: extensionKey, appPublicKey: appPublic) else {
            return BrowserWireMessage(type: .error, cid: cid, message: "invalid public key")
        }

        pruneStalePairings()
        pendingPairings[cid] = PendingPairing(
            secret: secret.withUnsafeBytes { Data($0) },
            extensionKey: extensionKey, verdict: .pending, createdAt: Date())

        // Ask the user out of band; the extension learns the verdict via
        // pairPoll (Safari can't be handed an unsolicited push).
        let delegate = self.delegate
        Task { [weak self] in
            let approved = await delegate.approveBrowserPairing(verificationCode: code)
            await self?.completePairing(cid: cid, approved: approved)
        }
        return BrowserWireMessage(type: .pairResponse, cid: cid, publicKey: appPublic.base64EncodedString())
    }

    private func completePairing(cid: String, approved: Bool) async {
        guard var pending = pendingPairings[cid] else { return }
        if approved {
            await pairings.savePairing(extensionKey: pending.extensionKey, secret: pending.secret)
            pending.verdict = .confirmed
        } else {
            pending.verdict = .rejected
        }
        pendingPairings[cid] = pending
    }

    private func handlePairPoll(_ cid: String?) -> BrowserWireMessage {
        guard let cid, let pending = pendingPairings[cid] else {
            return BrowserWireMessage(type: .error, cid: cid, message: "unknown pairing")
        }
        switch pending.verdict {
        case .pending:
            return BrowserWireMessage(type: .pairPending, cid: cid)
        case .confirmed:
            pendingPairings[cid] = nil
            return BrowserWireMessage(type: .pairConfirmed, cid: cid)
        case .rejected:
            pendingPairings[cid] = nil
            return BrowserWireMessage(type: .pairRejected, cid: cid)
        }
    }

    // MARK: Session

    private func handleSessionStart(_ message: BrowserWireMessage) async -> BrowserWireMessage {
        guard let cid = message.cid,
              let staticB64 = message.publicKey, let extensionKey = Data(base64Encoded: staticB64),
              let ephB64 = message.ephemeralKey, let extensionEphemeral = Data(base64Encoded: ephB64) else {
            return BrowserWireMessage(type: .error, cid: message.cid, message: "invalid session start")
        }
        guard let secretData = await pairings.pairingSecret(forExtensionKey: extensionKey) else {
            return BrowserWireMessage(type: .error, cid: cid, message: "not paired")
        }
        let appEphemeral = Curve25519.KeyAgreement.PrivateKey()
        let appEphemeralPublic = appEphemeral.publicKey.rawRepresentation
        guard let keys = try? BrowserChannelCrypto.sessionKeys(
            myEphemeral: appEphemeral, peerEphemeralPublicKey: extensionEphemeral,
            pairingSecret: SymmetricKey(data: secretData),
            extensionEphemeralPublicKey: extensionEphemeral, appEphemeralPublicKey: appEphemeralPublic) else {
            return BrowserWireMessage(type: .error, cid: cid, message: "invalid public key")
        }
        pruneStaleSessions()
        // A fresh session-start replaces any prior session for this cid (fresh
        // ephemerals → fresh keys → counters reset to 0).
        sessions[cid] = Session(
            extensionToApp: keys.extensionToApp, appToExtension: keys.appToExtension,
            receiveSeq: 0, sendSeq: 0, lastSeen: Date())
        return BrowserWireMessage(type: .sessionAccept, cid: cid, ephemeralKey: appEphemeralPublic.base64EncodedString())
    }

    private func handleEnc(_ message: BrowserWireMessage) async -> BrowserWireMessage {
        guard let cid = message.cid, var session = sessions[cid] else {
            return BrowserWireMessage(type: .error, cid: message.cid, message: "no session")
        }
        guard let plaintext = try? BrowserChannelCrypto.open(
                message, from: .extensionSide, expectedSeq: session.receiveSeq, key: session.extensionToApp),
              let request = try? JSONDecoder().decode(BrowserRequest.self, from: plaintext) else {
            // Desync or tampering: drop the session so the extension re-handshakes.
            sessions[cid] = nil
            return BrowserWireMessage(type: .error, cid: cid, message: "session desync")
        }
        // Reserve and commit the counter advance BEFORE awaiting the delegate,
        // so a duplicate/concurrent frame for the same cid (actor reentrancy)
        // is rejected by the seq check rather than reading stale state.
        let sendSeq = session.sendSeq
        session.receiveSeq += 1
        session.sendSeq += 1
        session.lastSeen = Date()
        sessions[cid] = session

        let response = await delegate.handleBrowserRequest(request)
        guard let payload = try? JSONEncoder().encode(response),
              var sealed = try? BrowserChannelCrypto.seal(payload, role: .app, seq: sendSeq, key: session.appToExtension) else {
            sessions[cid] = nil
            return BrowserWireMessage(type: .error, cid: cid, message: "seal failed")
        }
        sealed.cid = cid
        return sealed
    }

    // MARK: Expiry

    private func pruneStaleSessions() {
        let cutoff = Date().addingTimeInterval(-Self.sessionTTL)
        sessions = sessions.filter { $0.value.lastSeen > cutoff }
    }

    private func pruneStalePairings() {
        let cutoff = Date().addingTimeInterval(-Self.pairingTTL)
        pendingPairings = pendingPairings.filter { $0.value.createdAt > cutoff }
    }
}

/// Per-connection transport: frames the socket byte stream into wire messages,
/// hands each to the server for dispatch, and writes back the single reply.
/// Holds no session state — that lives in `BrowserBridgeServer`, keyed by cid.
private actor BridgeConnection {
    private let connection: NWConnection
    private weak var server: BrowserBridgeServer?
    private var buffer = Data()

    init(connection: NWConnection, server: BrowserBridgeServer) {
        self.connection = connection
        self.server = server
    }

    func run() async {
        connection.start(queue: DispatchQueue(label: "browser-bridge-connection"))
        do {
            while true {
                guard let chunk = try await receiveChunk() else { break }
                buffer += chunk
                for frame in try NativeMessageFraming.drainFrames(from: &buffer) {
                    let message = try NativeMessageFraming.decodeMessage(frame)
                    if let reply = await server?.handle(message) {
                        try await send(reply)
                    }
                }
            }
        } catch {
            try? await send(BrowserWireMessage(type: .error, message: "protocol error"))
        }
        connection.cancel()
    }

    // MARK: Network plumbing

    private func receiveChunk() async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }

    private func send(_ message: BrowserWireMessage) async throws {
        let data = try NativeMessageFraming.encodeMessage(message)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
}
