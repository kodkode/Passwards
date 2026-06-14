import Foundation
import CryptoKit

/// A parsed SSH key usable by the agent: it carries the public-key blob and the
/// private scalar, and can produce an SSH signature blob for a challenge.
///
/// Supports the modern key types CryptoKit can sign with — Ed25519 and ECDSA
/// (NIST P-256/384/521) — parsed from an unencrypted OpenSSH private key
/// (`-----BEGIN OPENSSH PRIVATE KEY-----`). RSA and passphrase-encrypted keys
/// are reported as unsupported rather than mishandled.
public struct SSHKey: Sendable, Equatable {
    public enum Algorithm: String, Sendable {
        case ed25519 = "ssh-ed25519"
        case ecdsaP256 = "ecdsa-sha2-nistp256"
        case ecdsaP384 = "ecdsa-sha2-nistp384"
        case ecdsaP521 = "ecdsa-sha2-nistp521"
    }

    public let algorithm: Algorithm
    /// The SSH public-key blob (`string keytype` + key fields), exactly as it
    /// appears in an `authorized_keys` line and the agent identities answer.
    public let publicKeyBlob: Data
    public let comment: String
    /// Raw private material: the 32-byte Ed25519 seed, or the EC private scalar.
    let privateScalar: Data

    // MARK: Public surface

    /// `SHA256:base64` fingerprint, matching `ssh-keygen -lf`.
    public var fingerprintSHA256: String {
        let digest = SHA256.hash(data: publicKeyBlob)
        let b64 = Data(digest).base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))
        return "SHA256:\(b64)"
    }

    /// `authorized_keys`-style one-liner: "<type> <base64 blob> <comment>".
    public var authorizedKeyLine: String {
        "\(algorithm.rawValue) \(publicKeyBlob.base64EncodedString()) \(comment)".trimmingCharacters(in: .whitespaces)
    }

    /// Produces an SSH signature blob (`string sig-format` + `string signature`)
    /// over `challenge`, as required by an agent SIGN_REQUEST response.
    public func sign(_ challenge: Data) throws -> Data {
        var writer = SSHWireWriter()
        switch algorithm {
        case .ed25519:
            let key = try Curve25519.Signing.PrivateKey(rawRepresentation: privateScalar)
            writer.writeString("ssh-ed25519")
            writer.writeString(try key.signature(for: challenge))
        case .ecdsaP256:
            let key = try P256.Signing.PrivateKey(rawRepresentation: privateScalar)
            writer.writeString("ecdsa-sha2-nistp256")
            writer.writeString(Self.encodeECDSASignature(try key.signature(for: challenge).rawRepresentation))
        case .ecdsaP384:
            let key = try P384.Signing.PrivateKey(rawRepresentation: privateScalar)
            writer.writeString("ecdsa-sha2-nistp384")
            writer.writeString(Self.encodeECDSASignature(try key.signature(for: challenge).rawRepresentation))
        case .ecdsaP521:
            let key = try P521.Signing.PrivateKey(rawRepresentation: privateScalar)
            writer.writeString("ecdsa-sha2-nistp521")
            writer.writeString(Self.encodeECDSASignature(try key.signature(for: challenge).rawRepresentation))
        }
        return writer.data
    }

    /// ECDSA raw signature (r||s) → SSH ECDSA signature blob (mpint r, mpint s).
    private static func encodeECDSASignature(_ raw: Data) -> Data {
        let half = raw.count / 2
        var writer = SSHWireWriter()
        writer.writeMPInt(Data(raw.prefix(half)))
        writer.writeMPInt(Data(raw.suffix(from: raw.startIndex + half)))
        return writer.data
    }

    // MARK: Parsing

    /// Parses a `-----BEGIN OPENSSH PRIVATE KEY-----` PEM. Throws
    /// `SSHWireError.encryptedKeyUnsupported` for passphrase-protected keys and
    /// `.unsupportedKeyType` for RSA / unknown types.
    public static func parseOpenSSHPrivateKey(_ pem: String) throws -> SSHKey {
        let body = pem
            .split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix("-----") }
            .joined()
        guard let raw = Data(base64Encoded: body) else { throw SSHWireError.malformedKey }

        var reader = SSHWireReader(raw)
        let magic = "openssh-key-v1\0"
        guard raw.count >= magic.utf8.count,
              String(decoding: raw.prefix(magic.utf8.count), as: UTF8.self) == magic else {
            throw SSHWireError.malformedKey
        }
        // Skip the 15-byte magic, then parse the header.
        reader = SSHWireReader(Data(raw.dropFirst(magic.utf8.count)))

        let cipher = try reader.readStringUTF8()
        _ = try reader.readString()  // kdfname
        _ = try reader.readString()  // kdfoptions
        guard cipher == "none" else { throw SSHWireError.encryptedKeyUnsupported }

        let keyCount = try reader.readUInt32()
        guard keyCount == 1 else { throw SSHWireError.malformedKey }

        let publicKeyBlob = try reader.readString()
        let privateSection = try reader.readString()

        var priv = SSHWireReader(privateSection)
        let check1 = try priv.readUInt32()
        let check2 = try priv.readUInt32()
        guard check1 == check2 else { throw SSHWireError.malformedKey }  // wrong passphrase / corrupt

        let keyType = try priv.readStringUTF8()
        switch keyType {
        case "ssh-ed25519":
            _ = try priv.readString()                // public key (32 bytes)
            let privateBlob = try priv.readString()  // 64 bytes: seed || public
            guard privateBlob.count == 64 else { throw SSHWireError.malformedKey }
            let comment = try priv.readStringUTF8()
            return SSHKey(algorithm: .ed25519, publicKeyBlob: publicKeyBlob,
                          comment: comment, privateScalar: Data(privateBlob.prefix(32)))

        case "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521":
            _ = try priv.readString()                // curve name
            _ = try priv.readString()                // public point Q
            let scalar = try priv.readString()       // mpint private d (may have leading 0x00)
            let comment = try priv.readStringUTF8()
            let algorithm = Algorithm(rawValue: keyType)!
            let width = Self.scalarWidth(for: algorithm)
            // Left-pad / trim the mpint to the fixed field width CryptoKit wants.
            var d = Data(scalar.drop { $0 == 0 })
            guard d.count <= width else { throw SSHWireError.malformedKey }
            if d.count < width { d = Data(repeating: 0, count: width - d.count) + d }
            return SSHKey(algorithm: algorithm, publicKeyBlob: publicKeyBlob,
                          comment: comment, privateScalar: d)

        default:
            throw SSHWireError.unsupportedKeyType(keyType)
        }
    }

    private static func scalarWidth(for algorithm: Algorithm) -> Int {
        switch algorithm {
        case .ed25519: 32
        case .ecdsaP256: 32
        case .ecdsaP384: 48
        case .ecdsaP521: 66
        }
    }
}
