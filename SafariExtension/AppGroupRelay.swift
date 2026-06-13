import Foundation
import Network
import os

/// Forwards one Safari native message to the running 2Password app over the
/// shared App Group Unix socket and returns the single reply.
///
/// A process-global actor: every (per-message) `SafariWebExtensionHandler`
/// instance funnels through `shared`, so the socket connection is reused across
/// `beginRequest` calls while the appex process happens to live, and lazily
/// reconnected after a reap or app restart. The actor serializes round trips, so
/// concurrent/re-entrant `beginRequest` invocations can't interleave frames on
/// the shared socket.
actor AppGroupRelay {
    static let shared = AppGroupRelay()

    /// Must match `BrowserBridgeServer.appGroupIdentifier` / `defaultSocketPath`.
    private static let appGroupIdentifier = "L5774582ZK.com.michael.twopassword"
    private static let socketFilename = "2pw.sock"

    private static let queue = DispatchQueue(label: "2pw-appgroup-relay")
    private static let log = Logger(subsystem: "com.michael.twopassword.SafariExtension", category: "relay")

    private enum RelayError: Error { case noContainer, closed }

    private static func unreachableData() -> Data {
        (try? JSONSerialization.data(withJSONObject:
            ["type": "error", "message": "Couldn’t reach 2Password. Make sure the app is running."])) ?? Data()
    }

    private var connection: NWConnection?
    private var buffer = Data()

    /// Forward one extension message (opaque JSON bytes) to the app and return
    /// its reply bytes, or an error JSON the extension can surface. Reconnects
    /// once on a stale/dropped socket. Dealing in `Data` keeps non-Sendable
    /// dictionaries from crossing the actor boundary.
    func roundTrip(_ payload: Data) async -> Data {
        for attempt in 0..<2 {
            do {
                let connection = try await connected()
                try await send(Self.frame(payload), over: connection)
                return try await readFrame(over: connection)
            } catch {
                Self.log.error("relay round trip failed (attempt \(attempt)): \(String(describing: error))")
                reset()
            }
        }
        return Self.unreachableData()
    }

    // MARK: Connection

    private func connected() async throws -> NWConnection {
        if let connection { return connection }
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier) else {
            throw RelayError.noContainer
        }
        let path = container.appendingPathComponent(Self.socketFilename).path
        let connection = NWConnection(to: .unix(path: path), using: .tcp)
        let gate = ResumeOnce()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.fire { cont.resume() }
                case .failed(let error), .waiting(let error):
                    // .waiting on a UNIX socket means "connection refused" — the
                    // app isn't running. Fail fast rather than retry forever.
                    gate.fire { cont.resume(throwing: error) }
                case .cancelled:
                    gate.fire { cont.resume(throwing: RelayError.closed) }
                default:
                    break
                }
            }
            connection.start(queue: Self.queue)
        }
        self.connection = connection
        return connection
    }

    private func reset() {
        connection?.cancel()
        connection = nil
        buffer = Data()
    }

    // MARK: Framing — must match TwoPasswordCore.NativeMessageFraming
    // (4-byte little-endian length prefix + UTF-8 JSON body).

    private static func frame(_ body: Data) -> Data {
        var length = UInt32(body.count).littleEndian
        return withUnsafeBytes(of: &length) { Data($0) } + body
    }

    private func takeFrame() -> Data? {
        guard buffer.count >= 4 else { return nil }
        let length = Int(buffer.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian)
        guard buffer.count >= 4 + length else { return nil }
        let frame = buffer.subdata(in: (buffer.startIndex + 4)..<(buffer.startIndex + 4 + length))
        buffer.removeFirst(4 + length)
        return frame
    }

    private func readFrame(over connection: NWConnection) async throws -> Data {
        while true {
            if let frame = takeFrame() { return frame }
            guard let chunk = try await receiveChunk(over: connection) else { throw RelayError.closed }
            buffer += chunk
        }
    }

    // MARK: Network plumbing

    private func send(_ data: Data, over connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    private func receiveChunk(over connection: NWConnection) async throws -> Data? {
        try await withCheckedThrowingContinuation { cont in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let error { cont.resume(throwing: error) }
                else if let data, !data.isEmpty { cont.resume(returning: data) }
                else if isComplete { cont.resume(returning: nil) }
                else { cont.resume(returning: Data()) }
            }
        }
    }
}

/// Resume a checked continuation exactly once, even though NWConnection's state
/// handler can fire from its queue concurrently with the awaiting task.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func fire(_ body: () -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard !fired else { return }
        fired = true
        body()
    }
}
