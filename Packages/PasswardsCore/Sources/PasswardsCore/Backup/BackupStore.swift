import Foundation
import GRDB

/// Reads the whole vault out of the database (+ attachment files) for a backup,
/// and writes it back on restore. Works on raw ciphertext rows — it never needs
/// to decrypt anything, so it can run purely at the storage layer.
public struct BackupStore: Sendable {
    let database: AppDatabase
    let attachmentsDirectory: URL

    public init(database: AppDatabase, attachmentsDirectory: URL) {
        self.database = database
        self.attachmentsDirectory = attachmentsDirectory
    }

    public enum StoreError: Error { case noAccount }

    /// Gathers every row plus each attachment's ciphertext file.
    public func collect() async throws -> (account: AccountRecord, contents: BackupContents) {
        let (account, vaults, items, versions, attachments) = try await database.writer.read { db in
            (
                try AccountRecord.fetchOne(db),
                try VaultRecord.fetchAll(db),
                try ItemRecord.fetchAll(db),
                try ItemVersionRecord.fetchAll(db),
                try AttachmentRecord.fetchAll(db)
            )
        }
        guard let account else { throw StoreError.noAccount }

        var files: [String: Data] = [:]
        for attachment in attachments {
            let url = attachmentsDirectory.appendingPathComponent(attachment.id)
            if let data = try? Data(contentsOf: url) { files[attachment.id] = data }
        }

        let contents = BackupContents(
            vaults: vaults, items: items, itemVersions: versions,
            attachments: attachments, attachmentFiles: files
        )
        return (account, contents)
    }

    /// Replaces the entire local vault with the backup's contents. Clears all
    /// rows + attachment files, then inserts the backup. Restored rows are marked
    /// `pending` with no CloudKit metadata so they re-sync cleanly.
    public func restore(account: AccountRecord, contents: BackupContents) async throws {
        try await database.writer.write { db in
            for table in ["itemVersion", "attachment", "item", "vault", "account", "tombstone", "accountKeyBackup"] {
                try db.execute(sql: "DELETE FROM \(table)")
            }

            try account.insert(db)

            for vault in contents.vaults {
                var v = vault
                v.syncState = "pending"
                try v.insert(db)
            }
            for item in contents.items {
                var i = item
                i.syncState = "pending"
                i.ckSystemFields = nil
                try i.insert(db)
            }
            for version in contents.itemVersions {
                var ver = version
                ver.id = nil // let the autoincrement assign a fresh row id
                try ver.insert(db)
            }
            for attachment in contents.attachments {
                var a = attachment
                a.syncState = "pending"
                try a.insert(db)
            }
        }

        // Attachment files (ciphertext) live on disk, outside the DB transaction.
        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        let existing = (try? FileManager.default.contentsOfDirectory(at: attachmentsDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in existing { try? FileManager.default.removeItem(at: file) }
        for (id, data) in contents.attachmentFiles {
            try data.write(to: attachmentsDirectory.appendingPathComponent(id), options: .atomic)
        }
    }
}
