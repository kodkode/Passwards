import Foundation
import CryptoKit
import Network

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
/// One connection per native-messaging host process (i.e. per browser).
public actor BrowserBridgeServer {
    public static func defaultSocketPath() -> String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("2Password", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("browser-bridge.sock").path
    }

    private let path: String
    private let delegate: BrowserBridgeDelegate
    private let pairings: BrowserPairingStore
    private var listener: NWListener?
    private var connectionTasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    public init(socketPath: String, delegate: BrowserBridgeDelegate, pairings: BrowserPairingStore) {
        self.path = socketPath
        self.delegate = delegate
        self.pairings = pairings
    }

    public func start() throws {
        guard listener == nil else { return }
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
            if case .ready = state {
                // Only this user may talk to the vault.
                chmod(path, 0o600)
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
        unlink(path)
    }

    private func adopt(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connectionTasks[id] = Task {
            await BridgeConnection(connection: connection, delegate: delegate, pairings: pairings).run()
            await self.forget(id)
        }
    }

    private func forget(_ id: ObjectIdentifier) {
        connectionTasks[id] = nil
    }
}

/// Per-connection protocol state machine: pairing or session handshake,
/// then sealed RPC dispatch.
private actor BridgeConnection {
    private let connection: NWConnection
    private let delegate: BrowserBridgeDelegate
    private let pairings: BrowserPairingStore

    private var buffer = Data()
    private var extensionToAppKey: SymmetricKey?
    private var appToExtensionKey: SymmetricKey?
    private var receiveSeq: UInt64 = 0
    private var sendSeq: UInt64 = 0

    init(connection: NWConnection, delegate: BrowserBridgeDelegate, pairings: BrowserPairingStore) {
        self.connection = connection
        self.delegate = delegate
        self.pairings = pairings
    }

    func run() async {
        connection.start(queue: DispatchQueue(label: "browser-bridge-connection"))
        do {
            while true {
                guard let chunk = try await receiveChunk() else { break }
                buffer += chunk
                for frame in try NativeMessageFraming.drainFrames(from: &buffer) {
                    try await handle(NativeMessageFraming.decodeMessage(frame))
                }
            }
        } catch {
            try? await send(BrowserWireMessage(type: .error, message: "protocol error"))
        }
        connection.cancel()
    }

    private func handle(_ message: BrowserWireMessage) async throws {
        switch message.type {
        case .pairRequest:
            try await handlePairing(message)
        case .sessionStart:
            try await handleSessionStart(message)
        case .enc:
            try await handleEncrypted(message)
        default:
            throw BrowserChannelCrypto.ChannelError.sequenceMismatch
        }
    }

    private func handlePairing(_ message: BrowserWireMessage) async throws {
        guard let keyB64 = message.publicKey, let extensionKey = Data(base64Encoded: keyB64), extensionKey.count == 32 else {
            throw BrowserChannelCrypto.ChannelError.invalidPublicKey
        }
        let appKeyPair = Curve25519.KeyAgreement.PrivateKey()
        let appPublic = appKeyPair.publicKey.rawRepresentation
        let (secret, code) = try BrowserChannelCrypto.pairing(
            myPrivateKey: appKeyPair, peerPublicKey: extensionKey,
            extensionPublicKey: extensionKey, appPublicKey: appPublic)

        // Send our key first so the extension can derive and display the
        // same code while the app shows its approval prompt.
        try await send(BrowserWireMessage(type: .pairResponse, publicKey: appPublic.base64EncodedString()))

        if await delegate.approveBrowserPairing(verificationCode: code) {
            await pairings.savePairing(extensionKey: extensionKey, secret: secret.withUnsafeBytes { Data($0) })
            try await send(BrowserWireMessage(type: .pairConfirmed))
        } else {
            try await send(BrowserWireMessage(type: .pairRejected))
        }
    }

    private func handleSessionStart(_ message: BrowserWireMessage) async throws {
        guard let staticB64 = message.publicKey, let extensionKey = Data(base64Encoded: staticB64),
              let ephB64 = message.ephemeralKey, let extensionEphemeral = Data(base64Encoded: ephB64) else {
            throw BrowserChannelCrypto.ChannelError.invalidPublicKey
        }
        guard let secretData = await pairings.pairingSecret(forExtensionKey: extensionKey) else {
            try await send(BrowserWireMessage(type: .error, message: "not paired"))
            connection.cancel()
            return
        }
        let appEphemeral = Curve25519.KeyAgreement.PrivateKey()
        let appEphemeralPublic = appEphemeral.publicKey.rawRepresentation
        let keys = try BrowserChannelCrypto.sessionKeys(
            myEphemeral: appEphemeral, peerEphemeralPublicKey: extensionEphemeral,
            pairingSecret: SymmetricKey(data: secretData),
            extensionEphemeralPublicKey: extensionEphemeral, appEphemeralPublicKey: appEphemeralPublic)
        extensionToAppKey = keys.extensionToApp
        appToExtensionKey = keys.appToExtension
        receiveSeq = 0
        sendSeq = 0
        try await send(BrowserWireMessage(type: .sessionAccept, ephemeralKey: appEphemeralPublic.base64EncodedString()))
    }

    private func handleEncrypted(_ message: BrowserWireMessage) async throws {
        guard let inKey = extensionToAppKey, let outKey = appToExtensionKey else {
            throw BrowserChannelCrypto.ChannelError.decryptFailed
        }
        let plaintext = try BrowserChannelCrypto.open(message, from: .extensionSide, expectedSeq: receiveSeq, key: inKey)
        receiveSeq += 1
        let request = try JSONDecoder().decode(BrowserRequest.self, from: plaintext)
        let response = await delegate.handleBrowserRequest(request)
        let sealed = try BrowserChannelCrypto.seal(JSONEncoder().encode(response), role: .app, seq: sendSeq, key: outKey)
        sendSeq += 1
        try await send(sealed)
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
