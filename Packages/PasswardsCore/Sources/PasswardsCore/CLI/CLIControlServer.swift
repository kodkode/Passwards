import Foundation
import Network
import os

/// Local control channel for the `passwards` CLI: a Unix-socket server speaking
/// framed JSON (`CLIRequest`/`CLIResponse`). Only runs when the user enables
/// command-line access; the socket is 0600, and the backend gates every secret
/// read behind Touch ID. Mirrors `SSHAgentServer`'s socket handling.
public actor CLIControlServer {
    static let maxMessageLength = 256 * 1024

    private let path: String
    private let backend: CLIControlBackend
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: Task<Void, Never>] = [:]

    private static let log = Logger(subsystem: "com.michael.passwards", category: "cli-control")

    public init(socketPath: String, backend: CLIControlBackend) {
        self.path = socketPath
        self.backend = backend
    }

    nonisolated public static func defaultSocketPath() -> String {
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: BrowserBridgeServer.appGroupIdentifier) {
            return container.appendingPathComponent("cli.sock").path
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".2password-cli.sock").path
    }

    public func start() throws {
        guard listener == nil else { return }
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
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
            case .ready: chmod(path, 0o600)
            case .failed(let error): CLIControlServer.log.error("listener failed: \(error, privacy: .public)")
            default: break
            }
        }
        listener.start(queue: DispatchQueue(label: "cli-control-listener"))
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
        let session = CLIControlConnection(connection: connection, backend: backend)
        connections[id] = Task {
            await session.run()
            await self.forget(id)
        }
    }

    private func forget(_ id: ObjectIdentifier) { connections[id] = nil }
}

/// One CLI client connection: frames the byte stream (4-byte big-endian length +
/// JSON), decodes a `CLIRequest`, dispatches, and writes back the `CLIResponse`.
private actor CLIControlConnection {
    private let connection: NWConnection
    private let backend: CLIControlBackend
    private var buffer = Data()

    init(connection: NWConnection, backend: CLIControlBackend) {
        self.connection = connection
        self.backend = backend
    }

    func run() async {
        connection.start(queue: DispatchQueue(label: "cli-control-connection"))
        do {
            while true {
                guard let chunk = try await receive() else { break }
                buffer += chunk
                while let message = try takeMessage() {
                    let response: CLIResponse
                    if let request = try? JSONDecoder().decode(CLIRequest.self, from: message) {
                        response = await backend.handle(request)
                    } else {
                        response = CLIResponse(error: "malformed request")
                    }
                    let body = (try? JSONEncoder().encode(response)) ?? Data("{}".utf8)
                    try await send(framed(body))
                }
            }
        } catch {
            // Drop the connection; the CLI is one-shot and just retries.
        }
        connection.cancel()
    }

    private func takeMessage() throws -> Data? {
        guard buffer.count >= 4 else { return nil }
        let length = buffer.prefix(4).reduce(Int(0)) { ($0 << 8) | Int($1) }
        guard length >= 1, length <= CLIControlServer.maxMessageLength else { throw CLIControlError.badFrame }
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

private enum CLIControlError: Error { case badFrame }
