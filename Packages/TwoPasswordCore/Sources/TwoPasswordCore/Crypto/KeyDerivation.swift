import Foundation
import CryptoKit
import CommonCrypto

/// Two-secret key derivation (2SKD), modeled on 1Password's published design:
///
///     password —NFKD→ PBKDF2-HMAC-SHA256(password, HKDF(salt, email), 650k) ─┐
///     secretKey —HKDF(secret, accountID)─────────────────────────────────────┴─XOR→ AUK
///
/// The Account Unlock Key (AUK) decrypts the wrapped master key and is never stored.
public enum KeyDerivation {
    public static let defaultIterations = 650_000
    public static let saltLength = 16

    /// Derives the Account Unlock Key.
    /// - Parameters:
    ///   - password: the account password as typed by the user.
    ///   - email: account email; lowercased and bound into the salt expansion.
    ///   - salt: the per-account random 16-byte salt stored alongside the vault.
    ///   - secretKey: the user's Secret Key.
    ///   - iterations: PBKDF2 iteration count (stored per account for future upgrades).
    public static func deriveAccountUnlockKey(
        password: String,
        email: String,
        salt: Data,
        secretKey: SecretKey,
        iterations: Int = defaultIterations
    ) throws -> SymmetricKey {
        let passwordArm = try passwordArm(password: password, email: email, salt: salt, iterations: iterations)
        let secretArm = secretKeyArm(secretKey: secretKey)
        let auk = xor(passwordArm, secretArm)
        return SymmetricKey(data: auk)
    }

    static func passwordArm(password: String, email: String, salt: Data, iterations: Int) throws -> Data {
        // NFKD normalization so the same password typed with different
        // Unicode compositions derives the same key.
        let normalized = password
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .decomposedStringWithCompatibilityMapping
        let expandedSalt = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: salt),
            salt: Data(email.lowercased().trimmingCharacters(in: .whitespaces).utf8),
            info: Data("PBES2g-HS256".utf8),
            outputByteCount: 32
        )
        return try pbkdf2SHA256(
            password: Data(normalized.utf8),
            salt: expandedSalt.withUnsafeBytes { Data($0) },
            iterations: iterations,
            outputByteCount: 32
        )
    }

    static func secretKeyArm(secretKey: SecretKey) -> Data {
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: secretKey.keyMaterial),
            salt: Data(secretKey.accountID.utf8),
            info: Data(SecretKey.version.utf8),
            outputByteCount: 32
        )
        return derived.withUnsafeBytes { Data($0) }
    }

    static func pbkdf2SHA256(password: Data, salt: Data, iterations: Int, outputByteCount: Int) throws -> Data {
        var output = Data(count: outputByteCount)
        let status = output.withUnsafeMutableBytes { outBytes in
            salt.withUnsafeBytes { saltBytes in
                password.withUnsafeBytes { pwBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwBytes.bindMemory(to: Int8.self).baseAddress,
                        password.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        outBytes.bindMemory(to: UInt8.self).baseAddress,
                        outputByteCount
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw CryptoError.keyDerivationFailed }
        return output
    }

    static func xor(_ a: Data, _ b: Data) -> Data {
        precondition(a.count == b.count)
        var out = Data(count: a.count)
        for i in 0..<a.count { out[i] = a[i] ^ b[i] }
        return out
    }

    /// Generates a fresh random salt for a new account.
    public static func generateSalt() throws -> Data {
        var salt = Data(count: saltLength)
        let status = salt.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, saltLength, $0.baseAddress!)
        }
        guard status == errSecSuccess else { throw CryptoError.randomGenerationFailed }
        return salt
    }
}
