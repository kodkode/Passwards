import Foundation
import CryptoKit
import Security

/// Account-level key lifecycle: creation and password unlock.
public enum AccountCrypto {
    /// Everything persisted for an account (none of it secret on its own).
    public struct AccountKeyRecord: Sendable, Equatable {
        public let accountID: String
        public let email: String
        public let kdfSalt: Data
        public let kdfIterations: Int
        /// Master key wrapped under the AUK. AAD = "account:<accountID>".
        public let encMasterKey: Data
        /// Whether an opt-in recovery code is currently active.
        public let recoveryEnabled: Bool
        /// `{ masterKey, secretKey }` sealed under the recovery-code-derived key.
        /// AAD = "recovery:<accountID>". Nil until recovery is first set up; set to
        /// random bytes (un-openable) when recovery is turned off, so a stale
        /// CloudKit copy can't be opened with the old code.
        public let recoveryBlob: Data?
        /// The recovery code string sealed under the master key (for re-viewing
        /// while unlocked). AAD = "recoverycode:<accountID>".
        public let encRecoveryCode: Data?

        public init(
            accountID: String,
            email: String,
            kdfSalt: Data,
            kdfIterations: Int,
            encMasterKey: Data,
            recoveryEnabled: Bool = false,
            recoveryBlob: Data? = nil,
            encRecoveryCode: Data? = nil
        ) {
            self.accountID = accountID
            self.email = email
            self.kdfSalt = kdfSalt
            self.kdfIterations = kdfIterations
            self.encMasterKey = encMasterKey
            self.recoveryEnabled = recoveryEnabled
            self.recoveryBlob = recoveryBlob
            self.encRecoveryCode = encRecoveryCode
        }
    }

    public struct NewAccount: Sendable {
        public let record: AccountKeyRecord
        public let secretKey: SecretKey
        public let masterKey: SymmetricKey
    }

    /// Creates a new account: generates Secret Key, salt, and master key, and
    /// wraps the master key under the derived AUK.
    public static func createAccount(email: String, password: String, iterations: Int = KeyDerivation.defaultIterations) throws -> NewAccount {
        let secretKey = try SecretKey.generate()
        let salt = try KeyDerivation.generateSalt()
        let auk = try KeyDerivation.deriveAccountUnlockKey(
            password: password, email: email, salt: salt, secretKey: secretKey, iterations: iterations
        )
        let masterKey = EncryptedBlob.generateKey()
        let encMasterKey = try EncryptedBlob.wrapKey(masterKey, under: auk, aad: "account:\(secretKey.accountID)")
        let record = AccountKeyRecord(
            accountID: secretKey.accountID,
            email: email,
            kdfSalt: salt,
            kdfIterations: iterations,
            encMasterKey: encMasterKey
        )
        return NewAccount(record: record, secretKey: secretKey, masterKey: masterKey)
    }

    /// Unlocks with password + Secret Key. Throws `CryptoError.decryptionFailed`
    /// when either credential is wrong.
    public static func unlock(record: AccountKeyRecord, password: String, secretKey: SecretKey) throws -> SymmetricKey {
        let auk = try KeyDerivation.deriveAccountUnlockKey(
            password: password,
            email: record.email,
            salt: record.kdfSalt,
            secretKey: secretKey,
            iterations: record.kdfIterations
        )
        return try EncryptedBlob.unwrapKey(record.encMasterKey, under: auk, aad: "account:\(record.accountID)")
    }

    /// Re-wraps the master key for a password change (Secret Key stays the same).
    public static func changePassword(
        record: AccountKeyRecord,
        masterKey: SymmetricKey,
        newPassword: String,
        secretKey: SecretKey
    ) throws -> AccountKeyRecord {
        let salt = try KeyDerivation.generateSalt()
        let auk = try KeyDerivation.deriveAccountUnlockKey(
            password: newPassword,
            email: record.email,
            salt: salt,
            secretKey: secretKey,
            iterations: record.kdfIterations
        )
        let encMasterKey = try EncryptedBlob.wrapKey(masterKey, under: auk, aad: "account:\(record.accountID)")
        return AccountKeyRecord(
            accountID: record.accountID,
            email: record.email,
            kdfSalt: salt,
            kdfIterations: record.kdfIterations,
            encMasterKey: encMasterKey,
            // Recovery material is independent of the password, so it carries
            // through a password change untouched.
            recoveryEnabled: record.recoveryEnabled,
            recoveryBlob: record.recoveryBlob,
            encRecoveryCode: record.encRecoveryCode
        )
    }

    // MARK: Recovery code

    /// The recovery code, by design, escrows BOTH the master key and the Secret
    /// Key — combined with the user's iCloud data it grants access, so the code
    /// must be guarded as strongly as the Secret Key. Its high entropy (~147 bits)
    /// makes the single-HKDF derivation safe.
    private struct RecoveryPayload: Codable {
        let masterKey: Data
        let secretKeyAccountID: String
        let secretKeySecret: String
    }

    static func recoveryWrappingKey(code: RecoveryCode, accountID: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: code.keyMaterial),
            salt: Data(accountID.utf8),
            info: Data("recovery-\(RecoveryCode.version)".utf8),
            outputByteCount: 32
        )
    }

    /// Generates a fresh recovery code and the blobs to persist for it.
    public static func enableRecovery(
        masterKey: SymmetricKey,
        secretKey: SecretKey,
        accountID: String
    ) throws -> (code: RecoveryCode, recoveryBlob: Data, encRecoveryCode: Data) {
        let code = try RecoveryCode.generate()
        let recoveryKey = recoveryWrappingKey(code: code, accountID: accountID)
        let payload = RecoveryPayload(
            masterKey: masterKey.withUnsafeBytes { Data($0) },
            secretKeyAccountID: secretKey.accountID,
            secretKeySecret: secretKey.secret
        )
        let recoveryBlob = try EncryptedBlob.seal(payload, key: recoveryKey, aad: "recovery:\(accountID)")
        let encRecoveryCode = try EncryptedBlob.seal(Data(code.formatted.utf8), key: masterKey, aad: "recoverycode:\(accountID)")
        return (code, recoveryBlob, encRecoveryCode)
    }

    /// Reconstructs the master key + Secret Key from a recovery blob and code.
    /// Throws `CryptoError.decryptionFailed` when the code is wrong.
    public static func recover(
        recoveryBlob: Data,
        code: RecoveryCode,
        accountID: String
    ) throws -> (masterKey: SymmetricKey, secretKey: SecretKey) {
        let recoveryKey = recoveryWrappingKey(code: code, accountID: accountID)
        let payload = try EncryptedBlob.open(RecoveryPayload.self, from: recoveryBlob, key: recoveryKey, aad: "recovery:\(accountID)")
        let masterKey = SymmetricKey(data: payload.masterKey)
        let secretKey = SecretKey(accountID: payload.secretKeyAccountID, secret: payload.secretKeySecret)
        return (masterKey, secretKey)
    }

    /// Decrypts the stored recovery code for re-viewing while unlocked.
    public static func revealRecoveryCode(
        encRecoveryCode: Data,
        masterKey: SymmetricKey,
        accountID: String
    ) throws -> String {
        let data = try EncryptedBlob.open(encRecoveryCode, key: masterKey, aad: "recoverycode:\(accountID)")
        return String(decoding: data, as: UTF8.self)
    }

    /// Random bytes used to overwrite (destroy) recovery material when recovery
    /// is turned off, so a stale CloudKit copy can't be opened with the old code.
    public static func recoveryTombstone() throws -> Data {
        var data = Data(count: 48)
        let status = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 48, $0.baseAddress!)
        }
        guard status == errSecSuccess else { throw CryptoError.randomGenerationFailed }
        return data
    }
}
