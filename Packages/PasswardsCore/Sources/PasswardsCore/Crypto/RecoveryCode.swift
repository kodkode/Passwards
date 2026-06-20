import Foundation
import Security

/// A high-entropy recovery code: an opt-in second path back into the account if
/// the master password is forgotten. Unlike the Secret Key it carries no account
/// ID — recovery is always performed against a known account record. Format:
/// `RC-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX` (30 random characters ≈ 147 bits).
///
/// The code is independent of the password, so it survives password changes. It
/// derives the key that wraps the recovery blob (master key + Secret Key); see
/// `AccountCrypto.enableRecovery`.
public struct RecoveryCode: Sendable, Equatable {
    /// Same unambiguous alphabet as the Secret Key (no 0/O, 1/I/L, U).
    public static let alphabet = SecretKey.alphabet
    public static let version = "RC"
    public static let length = 30

    /// The 30 random characters (without the version prefix).
    public let secret: String

    public init(secret: String) {
        self.secret = secret
    }

    /// Generates a fresh recovery code using the system CSPRNG.
    public static func generate() throws -> RecoveryCode {
        RecoveryCode(secret: try randomString(length: length))
    }

    private static func randomString(length: Int) throws -> String {
        var chars: [Character] = []
        chars.reserveCapacity(length)
        // Rejection sampling for an unbiased draw from the 30-char alphabet.
        while chars.count < length {
            var byte: UInt8 = 0
            let status = withUnsafeMutableBytes(of: &byte) {
                SecRandomCopyBytes(kSecRandomDefault, 1, $0.baseAddress!)
            }
            guard status == errSecSuccess else { throw CryptoError.randomGenerationFailed }
            if byte < 240 { // 240 = 8 * 30, largest multiple of 30 below 256
                chars.append(alphabet[Int(byte % 30)])
            }
        }
        return String(chars)
    }

    /// Canonical display format with dashes: `RC-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX`.
    public var formatted: String {
        var groups = [RecoveryCode.version]
        var rest = Array(secret)
        while !rest.isEmpty {
            groups.append(String(rest.prefix(5)))
            rest.removeFirst(min(5, rest.count))
        }
        return groups.joined(separator: "-")
    }

    /// Raw key material used for derivation (the 30 secret characters as UTF-8).
    public var keyMaterial: Data { Data(secret.utf8) }

    /// Parses user input: tolerant of dashes, spaces, and lowercase.
    public init?(parsing input: String) {
        let cleaned = input.uppercased().filter { !"- ".contains($0) }
        guard cleaned.hasPrefix(RecoveryCode.version) else { return nil }
        let body = cleaned.dropFirst(RecoveryCode.version.count)
        guard body.count == RecoveryCode.length,
              body.allSatisfy({ RecoveryCode.alphabet.contains($0) }) else { return nil }
        self.secret = String(body)
    }
}
