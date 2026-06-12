import Foundation
import CryptoKit

/// Crypto for the extension ⇄ app channel. Mirrors 1Password's model:
/// a one-time *pairing* establishes a long-lived shared secret the user
/// vouches for via a verification code; every connection then runs an
/// ephemeral *session* handshake authenticated by that secret, giving
/// forward secrecy and mutual authentication without certificates.
///
/// The browser side implements the same math with WebCrypto (X25519,
/// HKDF-SHA256, AES-256-GCM), so every label and byte order here is part
/// of the wire contract — change nothing without versioning.
public enum BrowserChannelCrypto {

    public enum Role: Sendable {
        case app
        case extensionSide

        var sendDirection: UInt32 {
            switch self {
            case .extensionSide: 1 // extension → app
            case .app: 2           // app → extension
            }
        }
    }

    public enum ChannelError: Error, Equatable {
        case invalidPublicKey
        case sequenceMismatch
        case decryptFailed
    }

    // MARK: Pairing

    /// Both sides call this with the two static public keys; the keys are
    /// ordered by role so both derive identical results.
    /// The 6-digit code is displayed in the app AND the extension; the user
    /// approving it in the app is what authenticates the extension's key.
    public static func pairing(
        myPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        peerPublicKey: Data,
        extensionPublicKey: Data,
        appPublicKey: Data
    ) throws -> (secret: SymmetricKey, verificationCode: String) {
        guard let peer = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKey) else {
            throw ChannelError.invalidPublicKey
        }
        let shared = try myPrivateKey.sharedSecretFromKeyAgreement(with: peer)
        let secret = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("2pw-browser-pairing-v1".utf8),
            sharedInfo: extensionPublicKey + appPublicKey,
            outputByteCount: 32
        )
        let codeKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: secret,
            info: Data("2pw-verification-code".utf8),
            outputByteCount: 4
        )
        let value = codeKey.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.bigEndian
        let code = String(format: "%06d", value % 1_000_000)
        return (secret, code)
    }

    // MARK: Session

    /// Per-connection keys derived from fresh ephemerals, bound to the
    /// pairing secret: a peer that doesn't hold it derives garbage and
    /// every GCM open fails.
    public static func sessionKeys(
        myEphemeral: Curve25519.KeyAgreement.PrivateKey,
        peerEphemeralPublicKey: Data,
        pairingSecret: SymmetricKey,
        extensionEphemeralPublicKey: Data,
        appEphemeralPublicKey: Data
    ) throws -> (extensionToApp: SymmetricKey, appToExtension: SymmetricKey) {
        guard let peer = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerEphemeralPublicKey) else {
            throw ChannelError.invalidPublicKey
        }
        let shared = try myEphemeral.sharedSecretFromKeyAgreement(with: peer)
        let material = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: pairingSecret.withUnsafeBytes { Data($0) },
            sharedInfo: Data("2pw-browser-session-v1".utf8) + extensionEphemeralPublicKey + appEphemeralPublicKey,
            outputByteCount: 64
        )
        let bytes = material.withUnsafeBytes { Data($0) }
        return (
            extensionToApp: SymmetricKey(data: bytes.prefix(32)),
            appToExtension: SymmetricKey(data: bytes.suffix(32))
        )
    }

    // MARK: Sealed RPC envelopes

    /// 12-byte nonce = 4-byte direction tag + 8-byte big-endian counter;
    /// the counter doubles as AAD so replayed or reordered envelopes fail.
    static func nonce(direction: UInt32, seq: UInt64) -> AES.GCM.Nonce {
        var data = Data()
        withUnsafeBytes(of: direction.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: seq.bigEndian) { data.append(contentsOf: $0) }
        return try! AES.GCM.Nonce(data: data)
    }

    public static func seal(_ plaintext: Data, role: Role, seq: UInt64, key: SymmetricKey) throws -> BrowserWireMessage {
        let direction = role.sendDirection
        let box = try AES.GCM.seal(
            plaintext,
            using: key,
            nonce: nonce(direction: direction, seq: seq),
            authenticating: Data("2pw-enc-\(direction)-\(seq)".utf8)
        )
        return BrowserWireMessage(type: .enc, seq: seq, payload: box.combined!.base64EncodedString())
    }

    /// `expectedSeq` enforces the strictly-increasing per-direction counter.
    public static func open(_ message: BrowserWireMessage, from sender: Role, expectedSeq: UInt64, key: SymmetricKey) throws -> Data {
        guard message.type == .enc, let seq = message.seq, seq == expectedSeq,
              let payload = message.payload, let combined = Data(base64Encoded: payload) else {
            throw ChannelError.sequenceMismatch
        }
        let direction = sender.sendDirection
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: key, authenticating: Data("2pw-enc-\(direction)-\(seq)".utf8))
        } catch {
            throw ChannelError.decryptFailed
        }
    }
}
