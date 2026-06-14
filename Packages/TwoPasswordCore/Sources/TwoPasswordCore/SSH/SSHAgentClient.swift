import Foundation
import CryptoKit

/// Client side of the SSH agent protocol for the CLI: connects to the agent
/// socket and lists the public identities it serves. Public-key material only —
/// it never asks for or receives a private key.
public enum SSHAgentClient {
    public struct Identity: Sendable, Equatable {
        public let keyType: String
        public let blob: Data
        public let comment: String

        /// `authorized_keys`-style line: "<type> <base64 blob> <comment>".
        public var authorizedKeyLine: String {
            "\(keyType) \(blob.base64EncodedString()) \(comment)".trimmingCharacters(in: .whitespaces)
        }

        /// `SHA256:base64` fingerprint, matching `ssh-add -l`.
        public var fingerprintSHA256: String {
            "SHA256:" + Data(SHA256.hash(data: blob)).base64EncodedString()
                .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        }
    }

    /// Parses an SSH_AGENT_IDENTITIES_ANSWER body into identities.
    public static func parseIdentitiesAnswer(_ response: Data) -> [Identity]? {
        var reader = SSHWireReader(response)
        guard (try? reader.readByte()) == SSHAgentProtocol.identitiesAnswer,
              let count = try? reader.readUInt32() else { return nil }
        var identities: [Identity] = []
        for _ in 0..<count {
            guard let blob = try? reader.readString(),
                  let comment = try? reader.readStringUTF8() else { return nil }
            var typeReader = SSHWireReader(blob)
            let keyType = (try? typeReader.readStringUTF8()) ?? "ssh-key"
            identities.append(Identity(keyType: keyType, blob: blob, comment: comment))
        }
        return identities
    }

    /// Connects to a Unix-socket agent, requests identities, and returns them.
    /// Blocking — for short-lived CLI use. nil if the socket can't be reached.
    public static func listIdentities(socketPath: String) -> [Identity]? {
        guard let response = request(Data([SSHAgentProtocol.requestIdentities]), socketPath: socketPath) else {
            return nil
        }
        return parseIdentitiesAnswer(response)
    }

    /// One blocking framed (4-byte big-endian length + body) request/response.
    static func request(_ message: Data, socketPath: String) -> Data? {
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
        guard length > 0, length <= 1_000_000 else { return nil }
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
