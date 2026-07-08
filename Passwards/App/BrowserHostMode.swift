import Foundation
import PasswardsCore

/// Native-messaging host: Chrome launches this same binary with
/// `--browser-host`, and we become a dumb byte pipe between the extension's
/// stdio (Chrome native-messaging framing) and the app's bridge socket
/// (same framing) — all crypto happens at the two ends.
nonisolated enum BrowserHostMode {
    static func run() -> Never {
        guard let firstMessage = readFirstMessage(from: 0) else {
            emitError("protocol error")
            exit(1)
        }

        var fd = connect()

        // App not running (or bridge not up yet): launch only for explicitly
        // user-initiated native messages.
        if fd < 0 {
            if firstMessage.message.allowLaunch == true {
                launchApp()
                for _ in 0..<40 where fd < 0 {
                    usleep(250_000)
                    fd = connect()
                }
            } else {
                emitError("Passwards isn’t running. Open the app and try again.", cid: firstMessage.message.cid)
                exit(1)
            }
        }
        guard fd >= 0 else {
            emitError("Passwards isn’t running. Open the app and try again.", cid: firstMessage.message.cid)
            exit(1)
        }

        guard writeAll(firstMessage.frame, to: fd) else {
            close(fd)
            emitError("Passwards isn’t running. Open the app and try again.", cid: firstMessage.message.cid)
            exit(1)
        }

        let socketFD = fd

        // socket → stdout on a second thread; stdin → socket here.
        let reader = Thread {
            pump(from: socketFD, to: 1)
            exit(0) // app closed the connection
        }
        reader.start()
        pump(from: 0, to: socketFD) // returns on stdin EOF = browser closed the port
        exit(0)
    }

    private struct FirstMessage {
        var frame: Data
        var message: BrowserWireMessage
    }

    private static func readFirstMessage(from source: Int32) -> FirstMessage? {
        guard let lengthBytes = readExactly(from: source, count: 4) else { return nil }
        let length = lengthBytes.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
        guard Int(length) <= NativeMessageFraming.maxFrameLength else { return nil }
        guard let body = readExactly(from: source, count: Int(length)),
              let message = try? NativeMessageFraming.decodeMessage(body) else {
            return nil
        }
        var frame = Data()
        frame.append(lengthBytes)
        frame.append(body)
        return FirstMessage(frame: frame, message: message)
    }

    private static func readExactly(from source: Int32, count: Int) -> Data? {
        var data = Data(count: count)
        var offset = 0
        let complete = data.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return count == 0 }
            while offset < count {
                let n = read(source, base.advanced(by: offset), count - offset)
                guard n > 0 else { return false }
                offset += n
            }
            return true
        }
        return complete ? data : nil
    }

    private static func connect() -> Int32 {
        let path = BrowserBridgeServer.defaultSocketPath()
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let ok = withUnsafeMutableBytes(of: &address.sun_path) { buffer -> Bool in
            let bytes = Array(path.utf8)
            guard bytes.count < buffer.count else { return false }
            buffer.copyBytes(from: bytes)
            return true
        }
        guard ok else { close(fd); return -1 }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { close(fd); return -1 }
        return fd
    }

    private static func launchApp() {
        // Launch the exact bundle this host binary lives in — `open -b` can
        // resolve the bundle ID to a different (or duplicate) copy.
        let bundle = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent() // MacOS
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent() // Passwards.app
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", bundle.path]
        try? process.run()
        process.waitUntilExit()
    }

    private static func pump(from source: Int32, to destination: Int32) {
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = read(source, &buffer, buffer.count)
            guard count > 0 else { return }
            let flushed = buffer.withUnsafeBytes { raw in
                var written = 0
                while written < count {
                    let n = write(destination, raw.baseAddress! + written, count - written)
                    guard n > 0 else { return false }
                    written += n
                }
                return true
            }
            guard flushed else { return }
        }
    }

    private static func writeAll(_ data: Data, to destination: Int32) -> Bool {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return true }
            var written = 0
            while written < raw.count {
                let n = write(destination, base.advanced(by: written), raw.count - written)
                guard n > 0 else { return false }
                written += n
            }
            return true
        }
    }

    /// Frame an error message to the extension so it can tell the user.
    private static func emitError(_ message: String, cid: String? = nil) {
        guard let frame = try? NativeMessageFraming.encodeMessage(
            BrowserWireMessage(type: .error, cid: cid, message: message)) else { return }
        _ = writeAll(frame, to: 1)
    }
}
