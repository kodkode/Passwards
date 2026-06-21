import Testing
import Foundation
import CryptoKit
@testable import PasswardsCore

@Suite("Encrypted backup")
struct BackupTests {
    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pwbackup-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Builds a populated source: account + vault + item (+ a version) + an attachment.
    private func seed(attachDir: URL) async throws -> (db: AppDatabase, account: AccountCrypto.NewAccount, itemID: String, attachID: String) {
        let db = try AppDatabase.inMemory()
        let keyStore = KeyStore()
        let account = try AccountCrypto.createAccount(email: "t@example.com", password: "pw", iterations: 1000)
        await keyStore.setMasterKey(account.masterKey)
        let vaults = VaultRepository(database: db, keyStore: keyStore)
        try await vaults.saveAccount(account.record)
        let vault = try await vaults.createVault(attributes: VaultAttributes(name: "Personal"))

        let items = ItemRepository(database: db, keyStore: keyStore)
        var item = VaultItem(vaultID: vault.id)
        item.overview = ItemOverview(title: "GitHub", subtitle: "michael", urls: ["https://github.com"], category: .login)
        item.details = ItemDetails(sections: [ItemSection(fields: [
            ItemField(label: "password", kind: .concealed, value: "hunter2", purpose: .password),
        ])], notes: "first")
        try await items.create(item)
        // A detail-changing save snapshots the prior payload into item history.
        var edited = item
        edited.details.notes = "second"
        try await items.update(edited)

        let attachStore = try AttachmentStore(database: db, keyStore: keyStore, directory: attachDir)
        let attachID = try await attachStore.add(data: Data("hello attachment".utf8), filename: "note.txt", itemID: item.id)

        return (db, account, item.id, attachID)
    }

    @Test("Round-trip: collect → encode → decode → openContents → restore")
    func roundTrip() async throws {
        let attachDir = try tempDir()
        let src = try await seed(attachDir: attachDir)

        let store = BackupStore(database: src.db, attachmentsDirectory: attachDir)
        let collected = try await store.collect()
        #expect(collected.contents.items.count == 1)
        #expect(collected.contents.itemVersions.count >= 1)
        #expect(collected.contents.attachmentFiles[src.attachID] != nil)

        let fileData = try BackupArchive.encode(
            account: collected.account, contents: collected.contents,
            masterKey: src.account.masterKey, createdAt: Date()
        )

        // Header is readable without any key.
        let file = try BackupArchive.decode(fileData)
        #expect(file.account.email == "t@example.com")
        #expect(file.version == BackupArchive.formatVersion)

        let contents = try BackupArchive.openContents(file, masterKey: src.account.masterKey)

        // Restore into a fresh database + attachment directory.
        let db2 = try AppDatabase.inMemory()
        let attachDir2 = try tempDir()
        try await BackupStore(database: db2, attachmentsDirectory: attachDir2).restore(account: file.account, contents: contents)

        // Unlock the restored DB with the same password + Secret Key and verify.
        let keyStore2 = KeyStore()
        let acct2 = try #require(await VaultRepository(database: db2, keyStore: keyStore2).account())
        let masterKey2 = try AccountCrypto.unlock(record: acct2.keyRecord, password: "pw", secretKey: src.account.secretKey)
        await keyStore2.setMasterKey(masterKey2)

        let items2 = try await ItemRepository(database: db2, keyStore: keyStore2).allItems()
        #expect(items2.count == 1)
        #expect(items2.first?.overview.title == "GitHub")
        #expect(items2.first?.details.notes == "second")

        let versionCount = try await db2.writer.read { try ItemVersionRecord.fetchCount($0) }
        #expect(versionCount >= 1)

        let attachStore2 = try AttachmentStore(database: db2, keyStore: keyStore2, directory: attachDir2)
        let restored = try await attachStore2.decrypt(attachmentID: src.attachID)
        #expect(String(decoding: restored, as: UTF8.self) == "hello attachment")
    }

    @Test("Wrong master key can't open the payload")
    func wrongKey() async throws {
        let attachDir = try tempDir()
        let src = try await seed(attachDir: attachDir)
        let collected = try await BackupStore(database: src.db, attachmentsDirectory: attachDir).collect()
        let fileData = try BackupArchive.encode(account: collected.account, contents: collected.contents, masterKey: src.account.masterKey, createdAt: Date())
        let file = try BackupArchive.decode(fileData)
        #expect(throws: CryptoError.self) {
            _ = try BackupArchive.openContents(file, masterKey: EncryptedBlob.generateKey())
        }
    }

    @Test("Restore replaces existing data")
    func restoreReplaces() async throws {
        let attachDir = try tempDir()
        let src = try await seed(attachDir: attachDir)
        let collected = try await BackupStore(database: src.db, attachmentsDirectory: attachDir).collect()
        let file = try BackupArchive.decode(try BackupArchive.encode(account: collected.account, contents: collected.contents, masterKey: src.account.masterKey, createdAt: Date()))
        let contents = try BackupArchive.openContents(file, masterKey: src.account.masterKey)

        // Target DB already has a DIFFERENT account + an extra vault.
        let db2 = try AppDatabase.inMemory()
        let ks2 = KeyStore()
        let other = try AccountCrypto.createAccount(email: "other@example.com", password: "x", iterations: 1000)
        await ks2.setMasterKey(other.masterKey)
        let vaults2 = VaultRepository(database: db2, keyStore: ks2)
        try await vaults2.saveAccount(other.record)
        _ = try await vaults2.createVault(attributes: VaultAttributes(name: "Junk"))

        try await BackupStore(database: db2, attachmentsDirectory: try tempDir()).restore(account: file.account, contents: contents)

        let acct2 = try #require(await vaults2.account())
        #expect(acct2.email == "t@example.com")   // replaced
        let vaultCount = try await db2.writer.read { try VaultRecord.fetchCount($0) }
        #expect(vaultCount == 1)                   // the "Junk" vault is gone
    }

    @Test("Decode rejects an unsupported newer version")
    func unsupportedVersion() async throws {
        let attachDir = try tempDir()
        let src = try await seed(attachDir: attachDir)
        let acct = try #require(await VaultRepository(database: src.db, keyStore: KeyStore()).account())
        let future = BackupFile(version: BackupArchive.formatVersion + 1, createdAt: Date(), account: acct, sealedContents: Data())
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(future)
        #expect(throws: BackupError.self) { _ = try BackupArchive.decode(data) }
    }

    /// Helper: collect + seal + open a backup of the seeded source.
    private func roundTrippedContents(_ src: (db: AppDatabase, account: AccountCrypto.NewAccount, itemID: String, attachID: String), attachDir: URL) async throws -> (account: AccountRecord, contents: BackupContents) {
        let collected = try await BackupStore(database: src.db, attachmentsDirectory: attachDir).collect()
        let file = try BackupArchive.decode(try BackupArchive.encode(
            account: collected.account, contents: collected.contents,
            masterKey: src.account.masterKey, createdAt: Date()))
        let contents = try BackupArchive.openContents(file, masterKey: src.account.masterKey)
        return (file.account, contents)
    }

    @Test("Restore clears the CloudKit sync-state token so the device re-bootstraps")
    func restoreClearsSyncState() async throws {
        let attachDir = try tempDir()
        let src = try await seed(attachDir: attachDir)
        let backup = try await roundTrippedContents(src, attachDir: attachDir)

        // Target simulates a device that has already synced: a persisted token.
        let db2 = try AppDatabase.inMemory()
        try await db2.setSyncMetaValue(Data("stale-token".utf8), key: SyncEngine.stateKey)
        #expect(try await db2.syncMetaValue(key: SyncEngine.stateKey) != nil)

        try await BackupStore(database: db2, attachmentsDirectory: try tempDir())
            .restore(account: backup.account, contents: backup.contents)

        // Wiped — start() will load state=nil and do a full server fetch+reconcile,
        // instead of resuming from a stale token and silently dropping synced items.
        #expect(try await db2.syncMetaValue(key: SyncEngine.stateKey) == nil)
    }

    @Test("Restore prunes the replaced vault's attachment files but keeps restored ones")
    func restorePrunesStaleAttachments() async throws {
        let attachDir = try tempDir()
        let src = try await seed(attachDir: attachDir)
        let backup = try await roundTrippedContents(src, attachDir: attachDir)

        // Target attachment dir already holds a stale file from a different vault.
        let attachDir2 = try tempDir()
        let staleID = UUID().uuidString
        try Data("stale".utf8).write(to: attachDir2.appendingPathComponent(staleID))

        let db2 = try AppDatabase.inMemory()
        try await BackupStore(database: db2, attachmentsDirectory: attachDir2)
            .restore(account: backup.account, contents: backup.contents)

        // Stale file pruned; restored ciphertext present and still decrypts.
        #expect(!FileManager.default.fileExists(atPath: attachDir2.appendingPathComponent(staleID).path))
        let ks2 = KeyStore()
        let acct2 = try #require(await VaultRepository(database: db2, keyStore: ks2).account())
        let mk2 = try AccountCrypto.unlock(record: acct2.keyRecord, password: "pw", secretKey: src.account.secretKey)
        await ks2.setMasterKey(mk2)
        let restored = try await AttachmentStore(database: db2, keyStore: ks2, directory: attachDir2)
            .decrypt(attachmentID: src.attachID)
        #expect(String(decoding: restored, as: UTF8.self) == "hello attachment")
    }

    @Test("Password-only backup strips the recovery escrow from the header")
    func passwordOnlyBackupStripsRecovery() throws {
        let key = EncryptedBlob.generateKey()
        let account = AccountRecord(
            id: "ACCT", email: "t@example.com",
            kdfSalt: Data(repeating: 1, count: 16), kdfIterations: 1000,
            encMasterKey: Data(repeating: 2, count: 60), createdAt: Date(),
            recoveryEnabled: true,
            recoveryBlob: Data(repeating: 3, count: 80),
            encRecoveryCode: Data(repeating: 4, count: 40))
        let contents = BackupContents(vaults: [], items: [], itemVersions: [], attachments: [], attachmentFiles: [:])

        // Default keeps the recovery escrow.
        let withRecovery = try BackupArchive.decode(try BackupArchive.encode(
            account: account, contents: contents, masterKey: key, createdAt: Date()))
        #expect(withRecovery.account.recoveryEnabled == true)
        #expect(withRecovery.account.recoveryBlob != nil)
        #expect(withRecovery.account.encRecoveryCode != nil)

        // includeRecovery:false strips it — a recovery code can no longer open it.
        let passwordOnly = try BackupArchive.decode(try BackupArchive.encode(
            account: account, contents: contents, masterKey: key, createdAt: Date(),
            includeRecovery: false))
        #expect(passwordOnly.account.recoveryEnabled == false)
        #expect(passwordOnly.account.recoveryBlob == nil)
        #expect(passwordOnly.account.encRecoveryCode == nil)
        // Stripping only touches the header; the payload still opens with the master key.
        #expect(try BackupArchive.openContents(passwordOnly, masterKey: key).items.isEmpty)
    }
}
