import Foundation
import CryptoKit

/// Holds decrypted keys while the vault is unlocked. `lock()` drops everything.
///
/// Key zeroization in Swift is best-effort: CryptoKit's SymmetricKey buffers
/// are freed but the runtime gives no hard guarantee about copies. This matches
/// the threat model of every Swift password manager.
public actor KeyStore {
    public private(set) var masterKey: SymmetricKey?
    private var vaultKeys: [String: SymmetricKey] = [:]

    public init() {}

    public var isUnlocked: Bool { masterKey != nil }

    public func setMasterKey(_ key: SymmetricKey) {
        masterKey = key
    }

    public func cacheVaultKey(_ key: SymmetricKey, vaultID: String) {
        vaultKeys[vaultID] = key
    }

    /// Unwraps and caches a vault key from its stored wrapped form.
    public func vaultKey(vaultID: String, encVaultKey: Data) throws -> SymmetricKey {
        if let cached = vaultKeys[vaultID] { return cached }
        guard let masterKey else { throw CryptoError.decryptionFailed }
        let key = try EncryptedBlob.unwrapKey(encVaultKey, under: masterKey, aad: "vault:\(vaultID)")
        vaultKeys[vaultID] = key
        return key
    }

    /// Unwraps an item key under its vault key (not cached; transient use).
    public func itemKey(itemID: String, encItemKey: Data, vaultID: String, encVaultKey: Data) throws -> SymmetricKey {
        let vKey = try vaultKey(vaultID: vaultID, encVaultKey: encVaultKey)
        return try EncryptedBlob.unwrapKey(encItemKey, under: vKey, aad: "item:\(itemID)")
    }

    public func lock() {
        masterKey = nil
        vaultKeys.removeAll()
    }
}
