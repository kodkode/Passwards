import Foundation
import CryptoKit
import GRDB

/// Item persistence. Encrypts on write, decrypts on read; every detail-changing
/// save snapshots the previous payload into `itemVersion` first.
public struct ItemRepository: Sendable {
    let database: AppDatabase
    let keyStore: KeyStore

    public init(database: AppDatabase, keyStore: KeyStore) {
        self.database = database
        self.keyStore = keyStore
    }

    private func itemKey(for record: ItemRecord) async throws -> SymmetricKey {
        guard let vaultRecord = try await database.writer.read({ db in
            try VaultRecord.fetchOne(db, key: record.vaultId)
        }) else { throw CryptoError.decryptionFailed }
        return try await keyStore.itemKey(
            itemID: record.id,
            encItemKey: record.encItemKey,
            vaultID: record.vaultId,
            encVaultKey: vaultRecord.encVaultKey
        )
    }

    // MARK: Create / update

    @discardableResult
    public func create(_ item: VaultItem) async throws -> VaultItem {
        guard let vaultRecord = try await database.writer.read({ db in
            try VaultRecord.fetchOne(db, key: item.vaultID)
        }) else { throw CryptoError.decryptionFailed }
        let vaultKey = try await keyStore.vaultKey(vaultID: item.vaultID, encVaultKey: vaultRecord.encVaultKey)
        let itemKey = EncryptedBlob.generateKey()
        let record = ItemRecord(
            id: item.id,
            vaultId: item.vaultID,
            encItemKey: try EncryptedBlob.wrapKey(itemKey, under: vaultKey, aad: "item:\(item.id)"),
            encOverview: try EncryptedBlob.seal(item.overview, key: itemKey, aad: "overview:\(item.id)"),
            encDetails: try EncryptedBlob.seal(item.details, key: itemKey, aad: "details:\(item.id)"),
            contentVersion: 1,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            trashedAt: item.trashedAt,
            syncState: "pending",
            ckSystemFields: nil
        )
        try await database.writer.write { db in
            try record.insert(db)
        }
        return item
    }

    /// Saves an edit. The previous payload is preserved as a version row.
    public func update(_ item: VaultItem) async throws {
        guard var record = try await database.writer.read({ db in
            try ItemRecord.fetchOne(db, key: item.id)
        }) else { throw CryptoError.decryptionFailed }
        let key = try await itemKey(for: record)

        let previousVersion = ItemVersionRecord(
            id: nil,
            itemId: record.id,
            versionNumber: record.contentVersion,
            encOverview: record.encOverview,
            encDetails: record.encDetails,
            editedAt: record.updatedAt
        )

        record.encOverview = try EncryptedBlob.seal(item.overview, key: key, aad: "overview:\(item.id)")
        record.encDetails = try EncryptedBlob.seal(item.details, key: key, aad: "details:\(item.id)")
        record.contentVersion += 1
        record.updatedAt = Date()
        record.trashedAt = item.trashedAt
        record.syncState = "pending"

        let updated = record
        try await database.writer.write { db in
            try previousVersion.insert(db)
            try updated.update(db)
        }
    }

    /// Overview-only update (favorite toggle, archive, tags) without a history entry.
    public func updateOverview(_ overview: ItemOverview, itemID: String) async throws {
        guard var record = try await database.writer.read({ db in
            try ItemRecord.fetchOne(db, key: itemID)
        }) else { throw CryptoError.decryptionFailed }
        let key = try await itemKey(for: record)
        record.encOverview = try EncryptedBlob.seal(overview, key: key, aad: "overview:\(itemID)")
        record.contentVersion += 1
        record.updatedAt = Date()
        record.syncState = "pending"
        let updated = record
        try await database.writer.write { db in
            try updated.update(db)
        }
    }

    // MARK: Read

    public func item(id: String) async throws -> VaultItem? {
        guard let record = try await database.writer.read({ db in
            try ItemRecord.fetchOne(db, key: id)
        }) else { return nil }
        let key = try await itemKey(for: record)
        return VaultItem(
            id: record.id,
            vaultID: record.vaultId,
            overview: try EncryptedBlob.open(ItemOverview.self, from: record.encOverview, key: key, aad: "overview:\(record.id)"),
            details: try EncryptedBlob.open(ItemDetails.self, from: record.encDetails, key: key, aad: "details:\(record.id)"),
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            trashedAt: record.trashedAt
        )
    }

    /// Decrypts all overviews (the unlock-time cache).
    public func allSummaries() async throws -> [ItemSummary] {
        let records = try await database.writer.read { db in
            try ItemRecord.fetchAll(db)
        }
        var summaries: [ItemSummary] = []
        summaries.reserveCapacity(records.count)
        for record in records {
            let key = try await itemKey(for: record)
            let overview = try EncryptedBlob.open(ItemOverview.self, from: record.encOverview, key: key, aad: "overview:\(record.id)")
            summaries.append(ItemSummary(
                id: record.id,
                vaultID: record.vaultId,
                overview: overview,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                trashedAt: record.trashedAt
            ))
        }
        return summaries
    }

    // MARK: Trash

    public func moveToTrash(itemID: String) async throws {
        try await setTrashed(itemID: itemID, date: Date())
    }

    public func restoreFromTrash(itemID: String) async throws {
        try await setTrashed(itemID: itemID, date: nil)
    }

    private func setTrashed(itemID: String, date: Date?) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: "UPDATE item SET trashedAt = ?, updatedAt = ?, syncState = 'pending' WHERE id = ?",
                arguments: [date, Date(), itemID]
            )
        }
    }

    public func deletePermanently(itemID: String) async throws {
        try await database.writer.write { db in
            try Self.tombstoneItems(db, ids: [itemID])
            _ = try ItemRecord.deleteOne(db, key: itemID)
        }
    }

    public func emptyTrash() async throws {
        try await database.writer.write { db in
            let ids = try String.fetchAll(db, sql: "SELECT id FROM item WHERE trashedAt IS NOT NULL")
            try Self.tombstoneItems(db, ids: ids)
            try db.execute(sql: "DELETE FROM item WHERE trashedAt IS NOT NULL")
        }
    }

    /// Permanently removes items trashed more than `days` days ago.
    /// Runs on plaintext columns only, so it works while locked.
    public func purgeTrash(olderThanDays days: Int = 30) async throws {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        try await database.writer.write { db in
            let ids = try String.fetchAll(db, sql: "SELECT id FROM item WHERE trashedAt IS NOT NULL AND trashedAt < ?", arguments: [cutoff])
            try Self.tombstoneItems(db, ids: ids)
            try db.execute(sql: "DELETE FROM item WHERE trashedAt IS NOT NULL AND trashedAt < ?", arguments: [cutoff])
        }
    }

    static func tombstoneItems(_ db: Database, ids: [String]) throws {
        for id in ids {
            try db.execute(
                sql: "INSERT INTO tombstone (recordName, deletedAt) VALUES (?, ?) ON CONFLICT(recordName) DO NOTHING",
                arguments: ["item-\(id)", Date()]
            )
        }
    }

    // MARK: History

    public struct DecryptedVersion: Sendable, Identifiable {
        public let id: Int64
        public let versionNumber: Int
        public let overview: ItemOverview
        public let details: ItemDetails
        public let editedAt: Date
    }

    public func versions(itemID: String) async throws -> [DecryptedVersion] {
        guard let record = try await database.writer.read({ db in
            try ItemRecord.fetchOne(db, key: itemID)
        }) else { return [] }
        let key = try await itemKey(for: record)
        let rows = try await database.writer.read { db in
            try ItemVersionRecord
                .filter(Column("itemId") == itemID)
                .order(Column("versionNumber").desc)
                .fetchAll(db)
        }
        return try rows.compactMap { row in
            guard let id = row.id else { return nil }
            return DecryptedVersion(
                id: id,
                versionNumber: row.versionNumber,
                overview: try EncryptedBlob.open(ItemOverview.self, from: row.encOverview, key: key, aad: "overview:\(itemID)"),
                details: try EncryptedBlob.open(ItemDetails.self, from: row.encDetails, key: key, aad: "details:\(itemID)"),
                editedAt: row.editedAt
            )
        }
    }

    /// Restores a historical version by saving it as a new edit.
    public func restoreVersion(_ version: DecryptedVersion, itemID: String) async throws {
        guard var item = try await item(id: itemID) else { return }
        item.overview = version.overview
        item.details = version.details
        try await update(item)
    }

    /// Moves an item (and its history/attachments) to another vault by
    /// re-wrapping its key under the destination vault key.
    public func move(itemID: String, toVault vaultID: String) async throws {
        guard let record = try await database.writer.read({ db in
            try ItemRecord.fetchOne(db, key: itemID)
        }), record.vaultId != vaultID else { return }
        guard let destVault = try await database.writer.read({ db in
            try VaultRecord.fetchOne(db, key: vaultID)
        }) else { throw CryptoError.decryptionFailed }
        let itemKey = try await self.itemKey(for: record)
        let destKey = try await keyStore.vaultKey(vaultID: vaultID, encVaultKey: destVault.encVaultKey)
        let rewrapped = try EncryptedBlob.wrapKey(itemKey, under: destKey, aad: "item:\(itemID)")
        try await database.writer.write { db in
            try db.execute(
                sql: "UPDATE item SET vaultId = ?, encItemKey = ?, updatedAt = ?, syncState = 'pending' WHERE id = ?",
                arguments: [vaultID, rewrapped, Date(), itemID]
            )
        }
    }
}
