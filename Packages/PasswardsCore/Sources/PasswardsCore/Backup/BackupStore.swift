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

    public enum StoreError: Error { case noAccount, insufficientDiskSpace }

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

    /// Replaces the entire local vault with the backup's contents. Restored rows
    /// are marked `pending` with no CloudKit metadata so they re-sync cleanly.
    ///
    /// The ordering is deliberate so the destructive DB swap is the single commit
    /// point and a crash can't lose data:
    ///   1. Pre-flight the free space the attachment ciphertext needs, BEFORE we
    ///      touch anything (`insufficientDiskSpace` aborts with the old vault intact).
    ///   2. Write the backup's attachment ciphertext to disk FIRST, via `.atomic`
    ///      writes. Restored attachments keep their original ids, so on a
    ///      same-device restore a colliding id overwrites the live file — but an
    ///      attachment's ciphertext is sealed once under a fixed UUID and never
    ///      rewritten, so any colliding id holds byte-identical bytes and the
    ///      atomic overwrite is content-preserving. What matters is that every
    ///      restored file is on disk BEFORE the single commit in step 3.
    ///   3. Clear + re-insert every row in ONE transaction. `syncMeta` is now in
    ///      the wipe list so the CKSyncEngine state token is reset: on the next
    ///      `start()` the device re-bootstraps a full fetch against the server
    ///      instead of resuming from a stale token and silently dropping
    ///      already-synced items the backup doesn't contain.
    ///   4. Prune the replaced vault's now-orphaned ciphertext (ids not restored).
    /// A crash before step 3 rolls back to the old vault (leaving only orphan
    /// files, garbage-collected later); a crash during/after step 3 still leaves
    /// every restored row's ciphertext already on disk — never a row pointing at
    /// a missing file.
    public func restore(account: AccountRecord, contents: BackupContents) async throws {
        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        try ensureDiskSpace(for: contents.attachmentFiles)

        for (id, data) in contents.attachmentFiles {
            try data.write(to: attachmentsDirectory.appendingPathComponent(id), options: .atomic)
        }

        try await database.writer.write { db in
            for table in ["itemVersion", "attachment", "item", "vault", "account", "tombstone", "accountKeyBackup", "syncMeta"] {
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

        // The DB now references only the backup's attachments; delete leftover
        // ciphertext from the replaced vault. Non-destructive to the restore.
        let restoredIDs = Set(contents.attachments.map(\.id))
        let existing = (try? FileManager.default.contentsOfDirectory(at: attachmentsDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in existing where !restoredIDs.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Ensures the volume backing the attachments directory can hold the backup's
    /// ciphertext (plus a margin for the DB write) BEFORE the destructive restore,
    /// so a disk-full can't leave the vault half-replaced. Best-effort: if the OS
    /// won't report capacity, it doesn't block the restore.
    private func ensureDiskSpace(for files: [String: Data]) throws {
        let needed = files.values.reduce(0) { $0 + $1.count }
        guard needed > 0 else { return }
        let values = try? attachmentsDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        guard let available = values?.volumeAvailableCapacityForImportantUsage else { return }
        if available < Int64(needed) + 16 * 1024 * 1024 {
            throw StoreError.insufficientDiskSpace
        }
    }
}
