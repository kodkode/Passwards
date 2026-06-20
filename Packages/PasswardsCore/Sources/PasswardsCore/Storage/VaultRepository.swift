import Foundation
import CryptoKit
import GRDB

/// Account + vault persistence with encryption at the boundary.
public struct VaultRepository: Sendable {
    let database: AppDatabase
    let keyStore: KeyStore

    public init(database: AppDatabase, keyStore: KeyStore) {
        self.database = database
        self.keyStore = keyStore
    }

    // MARK: Account

    public func account() async throws -> AccountRecord? {
        try await database.writer.read { db in
            try AccountRecord.fetchOne(db)
        }
    }

    public func saveAccount(_ record: AccountCrypto.AccountKeyRecord) async throws {
        try await database.writer.write { db in
            // Preserve the original creation date if a row already exists.
            let createdAt = try AccountRecord.fetchOne(db)?.createdAt ?? Date()
            let row = AccountRecord(
                id: record.accountID,
                email: record.email,
                kdfSalt: record.kdfSalt,
                kdfIterations: record.kdfIterations,
                encMasterKey: record.encMasterKey,
                createdAt: createdAt,
                recoveryEnabled: record.recoveryEnabled,
                recoveryBlob: record.recoveryBlob,
                encRecoveryCode: record.encRecoveryCode
            )
            try row.save(db)
        }
    }

    /// Turns on (or rotates) the recovery code. Updates only the recovery columns
    /// so the rest of the account row is untouched.
    public func setRecoveryFields(recoveryBlob: Data, encRecoveryCode: Data, accountID: String) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: "UPDATE account SET recoveryEnabled = 1, recoveryBlob = ?, encRecoveryCode = ? WHERE id = ?",
                arguments: [recoveryBlob, encRecoveryCode, accountID]
            )
        }
    }

    /// Turns off the recovery code. The blobs are overwritten with random,
    /// un-openable bytes (not NULLed) so that a stale CloudKit copy — which a
    /// freshly-built CKRecord can overwrite but not delete a field from — is
    /// replaced by garbage and can no longer be opened with the old code.
    public func disableRecovery(tombstone: Data, accountID: String) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: "UPDATE account SET recoveryEnabled = 0, recoveryBlob = ?, encRecoveryCode = ? WHERE id = ?",
                arguments: [tombstone, tombstone, accountID]
            )
        }
    }

    // MARK: Vaults

    @discardableResult
    public func createVault(attributes: VaultAttributes) async throws -> Vault {
        guard let masterKey = await keyStore.masterKey else { throw CryptoError.decryptionFailed }
        let vault = Vault(attributes: attributes)
        let vaultKey = EncryptedBlob.generateKey()
        let encVaultKey = try EncryptedBlob.wrapKey(vaultKey, under: masterKey, aad: "vault:\(vault.id)")
        let encAttributes = try EncryptedBlob.seal(attributes, key: vaultKey, aad: "vaultAttrs:\(vault.id)")
        let record = VaultRecord(
            id: vault.id,
            encVaultKey: encVaultKey,
            encAttributes: encAttributes,
            createdAt: vault.createdAt,
            syncState: "pending"
        )
        try await database.writer.write { db in
            try record.insert(db)
        }
        await keyStore.cacheVaultKey(vaultKey, vaultID: vault.id)
        return vault
    }

    public func updateVaultAttributes(_ attributes: VaultAttributes, vaultID: String) async throws {
        guard let record = try await vaultRecord(id: vaultID) else { return }
        let key = try await keyStore.vaultKey(vaultID: vaultID, encVaultKey: record.encVaultKey)
        let encAttributes = try EncryptedBlob.seal(attributes, key: key, aad: "vaultAttrs:\(vaultID)")
        try await database.writer.write { db in
            try db.execute(
                sql: "UPDATE vault SET encAttributes = ?, syncState = 'pending' WHERE id = ?",
                arguments: [encAttributes, vaultID]
            )
        }
    }

    /// Decrypts and returns all vaults. Also primes the KeyStore vault-key cache.
    public func allVaults() async throws -> [Vault] {
        let records = try await database.writer.read { db in
            try VaultRecord.order(Column("createdAt")).fetchAll(db)
        }
        var vaults: [Vault] = []
        for record in records {
            let key = try await keyStore.vaultKey(vaultID: record.id, encVaultKey: record.encVaultKey)
            let attributes = try EncryptedBlob.open(VaultAttributes.self, from: record.encAttributes, key: key, aad: "vaultAttrs:\(record.id)")
            vaults.append(Vault(id: record.id, attributes: attributes, createdAt: record.createdAt))
        }
        return vaults
    }

    public func vaultRecord(id: String) async throws -> VaultRecord? {
        try await database.writer.read { db in
            try VaultRecord.fetchOne(db, key: id)
        }
    }

    /// Deletes a vault and everything in it (irreversible).
    public func deleteVault(id: String) async throws {
        _ = try await database.writer.write { db in
            try VaultRecord.deleteOne(db, key: id)
        }
    }
}
