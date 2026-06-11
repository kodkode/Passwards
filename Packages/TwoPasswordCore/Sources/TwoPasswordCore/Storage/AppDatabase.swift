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

    /// Opens (creating if needed) the on-disk database in Application Support.
    public static func open() throws -> AppDatabase {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let dir = appSupport.appendingPathComponent("2Password", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA secure_delete = ON")
        }
        let pool = try DatabasePool(path: dir.appendingPathComponent("2password.sqlite").path, configuration: config)
        return try AppDatabase(writer: pool)
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
        return migrator
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

    public var keyRecord: AccountCrypto.AccountKeyRecord {
        .init(accountID: id, email: email, kdfSalt: kdfSalt, kdfIterations: kdfIterations, encMasterKey: encMasterKey)
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
