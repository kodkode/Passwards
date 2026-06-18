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
        guard let response = UnixSocketClient.request(
            Data([SSHAgentProtocol.requestIdentities]), socketPath: socketPath) else { return nil }
        return parseIdentitiesAnswer(response)
    }
}
