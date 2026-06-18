import Foundation
import Network
import os

/// A vault-backed OpenSSH agent listening on a Unix domain socket. Point
/// `SSH_AUTH_SOCK` at `socketPath` and `ssh`/`git` will list and use the SSH
/// Key items the backend exposes. Read-only: it answers REQUEST_IDENTITIES and
/// SIGN_REQUEST and fails everything else.
///
/// Security rests on the socket being mode 0600 in a per-user location plus the
/// backend's own gating (vault unlocked, optional per-signature approval).
public actor SSHAgentServer {
    /// 256 KiB — SSH agent messages are tiny (a key blob + a hash); anything
    /// larger is malformed and capped so a local peer can't exhaust memory.
    static let maxMessageLength = 256 * 1024

    private let path: String
    private let backend: SSHAgentBackend
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: Task<Void, Never>] = [:]

    private static let log = Logger(subsystem: "com.michael.passwards", category: "ssh-agent")

    public init(socketPath: String, backend: SSHAgentBackend) {
        self.path = socketPath
        self.backend = backend
    }

    public var socketPath: String { path }

    /// The agent socket's stable location: the shared App Group container so a
    /// non-sandboxed `ssh` can reach it (falling back to the home directory in
    /// unentitled contexts like the CLI in some setups, or tests).
    nonisolated public static func defaultSocketPath() -> String {
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: BrowserBridgeServer.appGroupIdentifier) {
            return container.appendingPathComponent("agent.sock").path
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".2password-agent.sock").path
    }

    public func start() throws {
        guard listener == nil else { return }
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        unlink(path)  // a stale socket file blocks bind

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
                chmod(path, 0o600)  // only this user may reach the agent
            case .failed(let error):
                SSHAgentServer.log.error("listener failed: \(error, privacy: .public)")
            default:
                break
            }
        }
        listener.start(queue: DispatchQueue(label: "ssh-agent-listener"))
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        for task in connections.values { task.cancel() }
        connections.removeAll()
        unlink(path)
    }

    private func adopt(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        let session = AgentConnection(connection: connection, backend: backend)
        connections[id] = Task {
            await session.run()
            await self.forget(id)
        }
    }

    private func forget(_ id: ObjectIdentifier) {
        connections[id] = nil
    }
}

/// One agent client connection: frames the byte stream into agent messages
/// (4-byte big-endian length + body), dispatches each, and writes the reply.
private actor AgentConnection {
    private let connection: NWConnection
    private let backend: SSHAgentBackend
    private var buffer = Data()

    init(connection: NWConnection, backend: SSHAgentBackend) {
        self.connection = connection
        self.backend = backend
    }

    func run() async {
        connection.start(queue: DispatchQueue(label: "ssh-agent-connection"))
        do {
            while true {
                guard let chunk = try await receive() else { break }
                buffer += chunk
                while let message = try takeMessage() {
                    let response = await SSHAgentProtocol.handle(message, backend: backend)
                    try await send(framed(response))
                }
            }
        } catch {
            // Drop the connection; ssh re-connects per invocation.
        }
        connection.cancel()
    }

    /// Pull one complete framed message out of `buffer`, or nil if incomplete.
    private func takeMessage() throws -> Data? {
        guard buffer.count >= 4 else { return nil }
        let length = buffer.prefix(4).reduce(Int(0)) { ($0 << 8) | Int($1) }
        guard length >= 1, length <= SSHAgentServer.maxMessageLength else {
            throw SSHWireError.malformedKey  // bogus frame length
        }
        guard buffer.count >= 4 + length else { return nil }
        let message = Data(buffer[(buffer.startIndex + 4)..<(buffer.startIndex + 4 + length)])
        buffer.removeFirst(4 + length)
        return message
    }

    private func framed(_ body: Data) -> Data {
        var framed = Data()
        withUnsafeBytes(of: UInt32(body.count).bigEndian) { framed.append(contentsOf: $0) }
        framed.append(body)
        return framed
    }

    private func receive() async throws -> Data? {
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

    private func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }
}
