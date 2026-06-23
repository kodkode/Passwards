import Foundation
import GRDB

/// SQLite database. Every sensitive column holds AES-GCM ciphertext; plaintext
/// is limited to IDs, timestamps, and sync bookkeeping.
public struct AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    public init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try migrator.migrate(writer)
    }

    /// The on-disk vault directory (…/Application Support/2Password). Holds the
    /// SQLite database, its WAL/SHM sidecars, and the `Attachments/` ciphertext.
    /// (Kept at the legacy name across the rename so existing data stays reachable.)
    public static func vaultDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return appSupport.appendingPathComponent("2Password", isDirectory: true)
    }

    /// Opens (creating if needed) the on-disk database in Application Support.
    public static func open() throws -> AppDatabase {
        let dir = try vaultDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA secure_delete = ON")
        }
        let pool = try DatabasePool(path: dir.appendingPathComponent("2password.sqlite").path, configuration: config)
        return try AppDatabase(writer: pool)
    }

    /// Permanently deletes the ENTIRE on-disk vault — database, WAL/SHM sidecars,
    /// and all attachment ciphertext. Used only by the explicit, gated "erase and
    /// start over" recovery path on the database-error screen. Irreversible.
    /// Callers MUST release any open `AppDatabase` first so the file handles are
    /// closed before the directory is removed.
    public static func destroyOnDiskVault() throws {
        let dir = try vaultDirectory()
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    /// In-memory database for tests.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(writer: DatabaseQueue())
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "account") { t in
                t.column("id", .text).primaryKey()
                t.column("email", .text).notNull()
                t.column("kdfSalt", .blob).notNull()
                t.column("kdfIterations", .integer).notNull()
                t.column("encMasterKey", .blob).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "vault") { t in
                t.column("id", .text).primaryKey()
                t.column("encVaultKey", .blob).notNull()
                t.column("encAttributes", .blob).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("syncState", .text).notNull().defaults(to: "pending")
            }
            try db.create(table: "item") { t in
                t.column("id", .text).primaryKey()
                t.column("vaultId", .text).notNull().indexed()
                    .references("vault", onDelete: .cascade)
                t.column("encItemKey", .blob).notNull()
                t.column("encOverview", .blob).notNull()
                t.column("encDetails", .blob).notNull()
                t.column("contentVersion", .integer).notNull().defaults(to: 1)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("trashedAt", .datetime)
                t.column("syncState", .text).notNull().defaults(to: "pending")
                t.column("ckSystemFields", .blob)
            }
            try db.create(table: "itemVersion") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("itemId", .text).notNull().indexed()
                    .references("item", onDelete: .cascade)
                t.column("versionNumber", .integer).notNull()
                t.column("encOverview", .blob).notNull()
                t.column("encDetails", .blob).notNull()
                t.column("editedAt", .datetime).notNull()
            }
            try db.create(table: "attachment") { t in
                t.column("id", .text).primaryKey()
                t.column("itemId", .text).notNull().indexed()
                    .references("item", onDelete: .cascade)
                t.column("encMetadata", .blob).notNull()
                t.column("fileSize", .integer).notNull()
                t.column("syncState", .text).notNull().defaults(to: "pending")
            }
            try db.create(table: "syncMeta") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .blob).notNull()
            }
        }
        migrator.registerMigration("v2-tombstones") { db in
            // Deletion tombstones so sync can propagate removals.
            try db.create(table: "tombstone") { t in
                t.column("recordName", .text).primaryKey()
                t.column("deletedAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v3-account-backup") { db in
            // Snapshots of the account's key material taken before an incoming
            // (unauthenticated) CloudKit Account record overwrites it, so a
            // rolled-back or hostile record can't permanently lock the user out.
            try db.create(table: "accountKeyBackup") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("accountId", .text).notNull()
                t.column("email", .text).notNull()
                t.column("kdfSalt", .blob).notNull()
                t.column("kdfIterations", .integer).notNull()
                t.column("encMasterKey", .blob).notNull()
                t.column("replacedAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v4-recovery-code") { db in
            // Opt-in recovery code (forgotten-password recovery). All nullable /
            // defaulted so existing rows and older synced records stay valid.
            try db.alter(table: "account") { t in
                t.add(column: "recoveryEnabled", .boolean).notNull().defaults(to: false)
                t.add(column: "recoveryBlob", .blob)      // master key + Secret Key sealed under the code
                t.add(column: "encRecoveryCode", .blob)   // the code sealed under the master key
            }
        }
        return migrator
    }

    // MARK: Sync metadata helpers

    public func syncMetaValue(key: String) async throws -> Data? {
        try await writer.read { db in
            try Data.fetchOne(db, sql: "SELECT value FROM syncMeta WHERE key = ?", arguments: [key])
        }
    }

    public func setSyncMetaValue(_ value: Data, key: String) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "INSERT INTO syncMeta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                arguments: [key, value]
            )
        }
    }

    // MARK: Account key adoption (with recovery backup)

    public static let maxAccountKeyBackups = 10

    /// Adopts a remote account key record (bootstrap, or a password change that
    /// re-wrapped the master key). Because the record is unauthenticated, the
    /// prior key material is snapshotted into `accountKeyBackup` BEFORE it is
    /// overwritten, so a rolled-back or hostile record can't permanently lock
    /// the user out — their last working KDF params + wrapped master key stay
    /// recoverable on-device. Returns true if the record was adopted.
    @discardableResult
    public func adoptRemoteAccount(_ incoming: AccountCrypto.AccountKeyRecord) async throws -> Bool {
        try await writer.write { db in
            let local = try AccountRecord.fetchOne(db)
            guard local == nil || local?.id == incoming.accountID else { return false }
            if let local, local.encMasterKey != incoming.encMasterKey
                || local.kdfSalt != incoming.kdfSalt
                || local.kdfIterations != incoming.kdfIterations {
                var backup = AccountKeyBackupRecord(
                    id: nil, accountId: local.id, email: local.email,
                    kdfSalt: local.kdfSalt, kdfIterations: local.kdfIterations,
                    encMasterKey: local.encMasterKey, replacedAt: Date())
                try backup.insert(db)
                try db.execute(sql: """
                    DELETE FROM accountKeyBackup WHERE id NOT IN
                    (SELECT id FROM accountKeyBackup ORDER BY replacedAt DESC, id DESC LIMIT ?)
                    """, arguments: [Self.maxAccountKeyBackups])
            }
            let row = AccountRecord(
                id: incoming.accountID, email: incoming.email,
                kdfSalt: incoming.kdfSalt, kdfIterations: incoming.kdfIterations,
                encMasterKey: incoming.encMasterKey,
                createdAt: local?.createdAt ?? Date(),
                recoveryEnabled: incoming.recoveryEnabled,
                recoveryBlob: incoming.recoveryBlob,
                encRecoveryCode: incoming.encRecoveryCode)
            try row.save(db)
            return true
        }
    }

    /// Recovery snapshots of prior account key material, newest first.
    public func accountKeyBackups() async throws -> [AccountKeyBackupRecord] {
        try await writer.read { db in
            try AccountKeyBackupRecord
                .order(sql: "replacedAt DESC, id DESC")
                .fetchAll(db)
        }
    }
}

// MARK: - Records

public struct AccountRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "account"
    public var id: String
    public var email: String
    public var kdfSalt: Data
    public var kdfIterations: Int
    public var encMasterKey: Data
    public var createdAt: Date
    /// Opt-in recovery code (forgotten-password recovery). Optional/defaulted so
    /// rows written before the v4 migration and older synced records decode.
    public var recoveryEnabled: Bool = false
    public var recoveryBlob: Data?
    public var encRecoveryCode: Data?

    public var keyRecord: AccountCrypto.AccountKeyRecord {
        .init(
            accountID: id, email: email, kdfSalt: kdfSalt, kdfIterations: kdfIterations,
            encMasterKey: encMasterKey, recoveryEnabled: recoveryEnabled,
            recoveryBlob: recoveryBlob, encRecoveryCode: encRecoveryCode
        )
    }
}

/// A recovery snapshot of the account's key material, captured before an
/// incoming remote Account record overwrote it.
public struct AccountKeyBackupRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "accountKeyBackup"
    public var id: Int64?
    public var accountId: String
    public var email: String
    public var kdfSalt: Data
    public var kdfIterations: Int
    public var encMasterKey: Data
    public var replacedAt: Date

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct VaultRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "vault"
    public var id: String
    public var encVaultKey: Data
    public var encAttributes: Data
    public var createdAt: Date
    public var syncState: String
}

public struct ItemRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "item"
    public var id: String
    public var vaultId: String
    public var encItemKey: Data
    public var encOverview: Data
    public var encDetails: Data
    public var contentVersion: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var trashedAt: Date?
    public var syncState: String
    public var ckSystemFields: Data?
}

public struct ItemVersionRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "itemVersion"
    public var id: Int64?
    public var itemId: String
    public var versionNumber: Int
    public var encOverview: Data
    public var encDetails: Data
    public var editedAt: Date

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct AttachmentRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "attachment"
    public var id: String
    public var itemId: String
    public var encMetadata: Data
    public var fileSize: Int
    public var syncState: String
}
