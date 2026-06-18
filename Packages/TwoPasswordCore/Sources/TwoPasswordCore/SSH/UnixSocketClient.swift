import Foundation

/// One blocking, framed (4-byte big-endian length + body) request/response over
/// a Unix-domain socket. Shared by the short-lived CLI clients (SSH agent +
/// control channel); not for the GUI's async paths.
enum UnixSocketClient {
    static func request(_ message: Data, socketPath: String, maxResponse: Int = 1_000_000) -> Data? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bound = withUnsafeMutableBytes(of: &address.sun_path) { buffer -> Bool in
            let bytes = Array(socketPath.utf8)
            guard bytes.count < buffer.count else { return false }
            buffer.copyBytes(from: bytes)
            return true
        }
        guard bound else { return nil }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }

        var framed = Data()
        withUnsafeBytes(of: UInt32(message.count).bigEndian) { framed.append(contentsOf: $0) }
        framed.append(message)
        guard writeAll(fd, framed) else { return nil }

        guard let header = readN(fd, 4) else { return nil }
        let length = header.reduce(Int(0)) { ($0 << 8) | Int($1) }
        guard length > 0, length <= maxResponse else { return nil }
        return readN(fd, length)
    }

    private static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            var written = 0
            while written < data.count {
                let n = write(fd, raw.baseAddress!.advanced(by: written), data.count - written)
                guard n > 0 else { return false }
                written += n
            }
            return true
        }
    }

    private static func readN(_ fd: Int32, _ count: Int) -> Data? {
        var buffer = [UInt8](repeating: 0, count: count)
        var got = 0
        while got < count {
            let n = buffer[got...].withUnsafeMutableBytes { read(fd, $0.baseAddress, count - got) }
            guard n > 0 else { return nil }
            got += n
        }
        return Data(buffer)
    }
}
