import Foundation
import CryptoKit

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

        public init(accountID: String, email: String, kdfSalt: Data, kdfIterations: Int, encMasterKey: Data) {
            self.accountID = accountID
            self.email = email
            self.kdfSalt = kdfSalt
            self.kdfIterations = kdfIterations
            self.encMasterKey = encMasterKey
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
            encMasterKey: encMasterKey
        )
    }
}
