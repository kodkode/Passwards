import Foundation
import CryptoKit

/// AES-256-GCM sealing/opening for everything stored at rest.
///
/// Every blob is bound to its owning record via additional authenticated data
/// (AAD = record UUID string), so a ciphertext copied between rows fails to open.
public enum EncryptedBlob {
    public static func seal(_ plaintext: Data, key: SymmetricKey, aad: String) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: Data(aad.utf8))
        guard let combined = box.combined else { throw CryptoError.invalidCiphertext }
        return combined
    }

    public static func open(_ ciphertext: Data, key: SymmetricKey, aad: String) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(box, using: key, authenticating: Data(aad.utf8))
        } catch {
            throw CryptoError.decryptionFailed
        }
    }

    public static func seal<T: Encodable>(_ value: T, key: SymmetricKey, aad: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try seal(encoder.encode(value), key: key, aad: aad)
    }

    public static func open<T: Decodable>(_ type: T.Type, from ciphertext: Data, key: SymmetricKey, aad: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: try open(ciphertext, key: key, aad: aad))
    }

    /// Generates a fresh random 256-bit key (vault keys, item keys, master key).
    public static func generateKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    /// Wraps (encrypts) one key under another.
    public static func wrapKey(_ key: SymmetricKey, under wrappingKey: SymmetricKey, aad: String) throws -> Data {
        try seal(key.withUnsafeBytes { Data($0) }, key: wrappingKey, aad: aad)
    }

    public static func unwrapKey(_ wrapped: Data, under wrappingKey: SymmetricKey, aad: String) throws -> SymmetricKey {
        SymmetricKey(data: try open(wrapped, key: wrappingKey, aad: aad))
    }
}
