import Foundation
import Security

/// The 128-bit-equivalent Secret Key, second factor of the two-secret key
/// derivation. Format: `A3-XXXXXX-XXXXXX-XXXXX-XXXXX-XXXXX-XXXXX` where the
/// first group is the account ID and the remaining 26 characters are random.
public struct SecretKey: Sendable, Equatable {
    /// Unambiguous alphabet: no 0/O, 1/I/L, U (matches 1Password's Base32-ish set).
    public static let alphabet = Array("23456789ABCDEFGHJKMNPQRSTVWXYZ")
    public static let version = "A3"
    public static let accountIDLength = 6
    public static let secretLength = 26

    public let accountID: String
    /// The 26 random characters (without version/account ID).
    public let secret: String

    public init(accountID: String, secret: String) {
        self.accountID = accountID
        self.secret = secret
    }

    /// Generates a fresh secret key using the system CSPRNG.
    public static func generate() throws -> SecretKey {
        SecretKey(
            accountID: try randomString(length: accountIDLength),
            secret: try randomString(length: secretLength)
        )
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

    /// Canonical display format with dashes: `A3-ABC123-XXXXXX-XXXXX-XXXXX-XXXXX-XXXXX`.
    public var formatted: String {
        var groups = [SecretKey.version, accountID]
        var rest = Array(secret)
        let sizes = [6, 5, 5, 5, 5]
        for size in sizes {
            groups.append(String(rest.prefix(size)))
            rest.removeFirst(min(size, rest.count))
        }
        return groups.joined(separator: "-")
    }

    /// Raw key material used for derivation (the 26 secret characters as UTF-8).
    public var keyMaterial: Data { Data(secret.utf8) }

    /// Parses user input: tolerant of dashes, spaces, and lowercase.
    public init?(parsing input: String) {
        let cleaned = input.uppercased().filter { !"- ".contains($0) }
        guard cleaned.hasPrefix(SecretKey.version) else { return nil }
        let body = cleaned.dropFirst(SecretKey.version.count)
        guard body.count == SecretKey.accountIDLength + SecretKey.secretLength,
              body.allSatisfy({ SecretKey.alphabet.contains($0) }) else { return nil }
        self.accountID = String(body.prefix(SecretKey.accountIDLength))
        self.secret = String(body.dropFirst(SecretKey.accountIDLength))
    }
}

public enum CryptoError: Error, Sendable {
    case randomGenerationFailed
    case keyDerivationFailed
    case decryptionFailed
    case invalidCiphertext
    case keychainError(OSStatus)
    case biometricUnavailable
    case secureEnclaveFailed
}
