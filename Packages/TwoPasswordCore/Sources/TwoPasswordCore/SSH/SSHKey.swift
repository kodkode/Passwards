import Foundation
import CryptoKit
import Security

/// A parsed SSH key usable by the agent: it carries the public-key blob and the
/// private material, and can produce an SSH signature blob for a challenge.
///
/// Supports Ed25519, ECDSA (NIST P-256/384/521) via CryptoKit, and RSA via the
/// Security framework, parsed from an UNENCRYPTED OpenSSH private key
/// (`-----BEGIN OPENSSH PRIVATE KEY-----`). Passphrase-encrypted keys are
/// reported as unsupported rather than mishandled.
public struct SSHKey: Sendable, Equatable {
    public enum Algorithm: String, Sendable {
        case ed25519 = "ssh-ed25519"
        case ecdsaP256 = "ecdsa-sha2-nistp256"
        case ecdsaP384 = "ecdsa-sha2-nistp384"
        case ecdsaP521 = "ecdsa-sha2-nistp521"
        case rsa = "ssh-rsa"
    }

    enum Material: Sendable, Equatable {
        case raw(Data)   // Ed25519 seed or EC private scalar
        case rsa(n: Data, e: Data, d: Data, p: Data, q: Data, iqmp: Data)
    }

    public let algorithm: Algorithm
    /// The SSH public-key blob (`string keytype` + key fields), exactly as it
    /// appears in an `authorized_keys` line and the agent identities answer.
    public let publicKeyBlob: Data
    public let comment: String
    let material: Material

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
    /// over `challenge`, as required by an agent SIGN_REQUEST response. `flags`
    /// are the agent SIGN_REQUEST flags (SSH_AGENT_RSA_SHA2_256/512); they only
    /// affect RSA, which can sign as ssh-rsa / rsa-sha2-256 / rsa-sha2-512.
    public func sign(_ challenge: Data, flags: UInt32 = 0) throws -> Data {
        var writer = SSHWireWriter()
        switch algorithm {
        case .ed25519:
            let key = try Curve25519.Signing.PrivateKey(rawRepresentation: rawScalar())
            writer.writeString("ssh-ed25519")
            writer.writeString(try key.signature(for: challenge))
        case .ecdsaP256:
            let key = try P256.Signing.PrivateKey(rawRepresentation: rawScalar())
            writer.writeString("ecdsa-sha2-nistp256")
            writer.writeString(Self.encodeECDSASignature(try key.signature(for: challenge).rawRepresentation))
        case .ecdsaP384:
            let key = try P384.Signing.PrivateKey(rawRepresentation: rawScalar())
            writer.writeString("ecdsa-sha2-nistp384")
            writer.writeString(Self.encodeECDSASignature(try key.signature(for: challenge).rawRepresentation))
        case .ecdsaP521:
            let key = try P521.Signing.PrivateKey(rawRepresentation: rawScalar())
            writer.writeString("ecdsa-sha2-nistp521")
            writer.writeString(Self.encodeECDSASignature(try key.signature(for: challenge).rawRepresentation))
        case .rsa:
            guard case let .rsa(n, e, d, p, q, iqmp) = material else { throw SSHWireError.malformedKey }
            let (secAlgorithm, format) = Self.rsaVariant(flags: flags)
            let signature = try SSHRSA.sign(data: challenge, n: n, e: e, d: d, p: p, q: q, iqmp: iqmp,
                                            algorithm: secAlgorithm)
            writer.writeString(format)
            writer.writeString(signature)
        }
        return writer.data
    }

    private func rawScalar() throws -> Data {
        guard case let .raw(scalar) = material else { throw SSHWireError.malformedKey }
        return scalar
    }

    /// Map the agent SIGN_REQUEST flags to the RSA hash + SSH signature format.
    private static func rsaVariant(flags: UInt32) -> (SecKeyAlgorithm, String) {
        if flags & 0x04 != 0 { return (.rsaSignatureMessagePKCS1v15SHA512, "rsa-sha2-512") }
        if flags & 0x02 != 0 { return (.rsaSignatureMessagePKCS1v15SHA256, "rsa-sha2-256") }
        return (.rsaSignatureMessagePKCS1v15SHA1, "ssh-rsa")
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
        // Take the base64 between the armor markers and drop ALL whitespace, so
        // a key whose newlines were stripped (e.g. pasted into a single-line
        // field) still parses.
        let begin = "-----BEGIN OPENSSH PRIVATE KEY-----"
        let end = "-----END OPENSSH PRIVATE KEY-----"
        guard let beginRange = pem.range(of: begin),
              let endRange = pem.range(of: end, range: beginRange.upperBound..<pem.endIndex) else {
            throw SSHWireError.malformedKey
        }
        let base64 = pem[beginRange.upperBound..<endRange.lowerBound].filter { !$0.isWhitespace }
        guard let raw = Data(base64Encoded: String(base64)) else { throw SSHWireError.malformedKey }

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
                          comment: comment, material: .raw(Data(privateBlob.prefix(32))))

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
                          comment: comment, material: .raw(d))

        case "ssh-rsa":
            // OpenSSH private order: n, e, d, iqmp, p, q.
            let n = try priv.readString()
            let e = try priv.readString()
            let d = try priv.readString()
            let iqmp = try priv.readString()
            let p = try priv.readString()
            let q = try priv.readString()
            let comment = try priv.readStringUTF8()
            return SSHKey(algorithm: .rsa, publicKeyBlob: publicKeyBlob, comment: comment,
                          material: .rsa(n: n, e: e, d: d, p: p, q: q, iqmp: iqmp))

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
        case .rsa: 0   // not a fixed-width scalar; never reached for RSA
        }
    }
}
