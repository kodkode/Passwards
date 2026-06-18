import Foundation

/// Supplies identities and signatures to the SSH agent. Implemented by the app
/// over the unlocked vault; kept abstract here so the protocol is testable.
public protocol SSHAgentBackend: Sendable {
    /// Public-key blob + comment for every available SSH Key item.
    func identities() async -> [(blob: Data, comment: String)]
    /// Sign `data` with the key whose public blob is `keyBlob`. `flags` are the
    /// SIGN_REQUEST flags (SSH_AGENT_RSA_SHA2_256/512). Returns the SSH signature
    /// blob, or nil if there is no such key or the user declined.
    func sign(keyBlob: Data, data: Data, flags: UInt32) async -> Data?
}

/// The OpenSSH agent protocol (draft-miller-ssh-agent): length-prefixed
/// messages of `byte type` + type-specific body. `handle` turns one request
/// body into one response body; the socket layer adds framing.
public enum SSHAgentProtocol {
    // Requests (client → agent)
    static let requestIdentities: UInt8 = 11
    static let signRequest: UInt8 = 13
    // Responses (agent → client)
    static let agentFailure: UInt8 = 5
    static let agentSuccess: UInt8 = 6
    static let identitiesAnswer: UInt8 = 12
    static let signResponse: UInt8 = 14

    static let failure = Data([agentFailure])

    /// Handles one decoded agent message (type byte + body) and returns the
    /// response body. Unknown requests get SSH_AGENT_FAILURE, which is the
    /// protocol's "I don't support that" — clients fall back gracefully.
    public static func handle(_ message: Data, backend: SSHAgentBackend) async -> Data {
        guard let type = message.first else { return failure }
        var reader = SSHWireReader(Data(message.dropFirst()))

        switch type {
        case requestIdentities:
            let identities = await backend.identities()
            var writer = SSHWireWriter()
            writer.writeByte(identitiesAnswer)
            writer.writeUInt32(UInt32(identities.count))
            for identity in identities {
                writer.writeString(identity.blob)
                writer.writeString(identity.comment)
            }
            return writer.data

        case signRequest:
            guard let keyBlob = try? reader.readString(),
                  let data = try? reader.readString() else { return failure }
            let flags = (try? reader.readUInt32()) ?? 0   // RSA SHA2 selection
            guard let signature = await backend.sign(keyBlob: keyBlob, data: data, flags: flags) else {
                return failure
            }
            var writer = SSHWireWriter()
            writer.writeByte(signResponse)
            writer.writeString(signature)
            return writer.data

        default:
            // ADD/REMOVE/LOCK/etc. — this agent is read-only and vault-backed.
            return failure
        }
    }
}
