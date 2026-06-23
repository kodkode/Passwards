import Testing
import Foundation
@testable import PasswardsCore

/// Builds an unlocked in-memory environment for repository tests.
struct TestEnvironment {
    let database: AppDatabase
    let keyStore: KeyStore
    let vaults: VaultRepository
    let items: ItemRepository
    let vault: Vault

    static func make() async throws -> TestEnvironment {
        let database = try AppDatabase.inMemory()
        let keyStore = KeyStore()
        let account = try AccountCrypto.createAccount(email: "t@example.com", password: "pw", iterations: 1000)
        await keyStore.setMasterKey(account.masterKey)
        let vaults = VaultRepository(database: database, keyStore: keyStore)
        try await vaults.saveAccount(account.record)
        let vault = try await vaults.createVault(attributes: VaultAttributes(name: "Personal"))
        let items = ItemRepository(database: database, keyStore: keyStore)
        return TestEnvironment(database: database, keyStore: keyStore, vaults: vaults, items: items, vault: vault)
    }
}

@Suite("Storage")
struct StorageTests {
    func sampleLogin(vaultID: String) -> VaultItem {
        var item = VaultItem(vaultID: vaultID)
        item.overview = ItemOverview(title: "GitHub", subtitle: "michael", urls: ["https://github.com"], category: .login)
        item.details = ItemDetails(sections: [
            ItemSection(fields: [
                ItemField(label: "username", kind: .text, value: "michael", purpose: .username),
                ItemField(label: "password", kind: .concealed, value: "hunter2", purpose: .password),
            ])
        ], notes: "my note")
        return item
    }

    @Test func remoteAccountAdoptionBacksUpPriorKeyMaterial() async throws {
        let env = try await TestEnvironment.make()
        let original = try await env.database.writer.read { try AccountRecord.fetchOne($0)! }

        func incoming(salt: UInt8, key: UInt8) -> AccountCrypto.AccountKeyRecord {
            .init(accountID: original.id, email: original.email,
                  kdfSalt: Data(repeating: salt, count: 16), kdfIterations: 650_000,
                  encMasterKey: Data(repeating: key, count: 60))
        }

        // Re-adopting identical key material makes no backup.
        try await env.database.adoptRemoteAccount(original.keyRecord)
        #expect(try await env.database.accountKeyBackups().isEmpty)

        // A password-change-style record backs up the OLD material, adopts NEW.
        let adopted = try await env.database.adoptRemoteAccount(incoming(salt: 9, key: 9))
        #expect(adopted)
        let backups = try await env.database.accountKeyBackups()
        #expect(backups.count == 1)
        #expect(backups[0].encMasterKey == original.encMasterKey)  // prior key recoverable
        #expect(backups[0].kdfSalt == original.kdfSalt)
        let active = try await env.database.writer.read { try AccountRecord.fetchOne($0)! }
        #expect(active.encMasterKey == Data(repeating: 9, count: 60))

        // A record for a different account is refused outright.
        let foreign = AccountCrypto.AccountKeyRecord(
            accountID: "OTHER", email: "x", kdfSalt: Data([1]), kdfIterations: 1, encMasterKey: Data([1]))
        #expect(try await env.database.adoptRemoteAccount(foreign) == false)

        // Backup history is capped.
        for i in 0..<(AppDatabase.maxAccountKeyBackups + 5) {
            try await env.database.adoptRemoteAccount(incoming(salt: UInt8(20 + i), key: UInt8(100 + i)))
        }
        #expect(try await env.database.accountKeyBackups().count <= AppDatabase.maxAccountKeyBackups)
    }

    @Test func vaultRoundTrip() async throws {
        let env = try await TestEnvironment.make()
        let all = try await env.vaults.allVaults()
        #expect(all.map(\.attributes.name) == ["Personal"])

        var attrs = all[0].attributes
        attrs.name = "Renamed"
        try await env.vaults.updateVaultAttributes(attrs, vaultID: all[0].id)
        // Fresh KeyStore with the same master key = re-unlock simulation.
        let store2 = KeyStore()
        if let master = await env.keyStore.masterKey {
            await store2.setMasterKey(master)
        }
        let repo2 = VaultRepository(database: env.database, keyStore: store2)
        let reloaded = try await repo2.allVaults()
        #expect(reloaded.map(\.attributes.name) == ["Renamed"])
    }

    /// Onboarding must never overwrite an existing vault. If bootstrap hit a
    /// recoverable error (e.g. an undecodable account row) and fell back to
    /// onboarding, a second `createInitialAccount` would orphan the master key —
    /// so it must be refused, leaving the original account intact.
    @Test func createInitialAccountRefusesExistingAccount() async throws {
        let database = try AppDatabase.inMemory()
        let vaults = VaultRepository(database: database, keyStore: KeyStore())

        #expect(try await vaults.hasAccount() == false)

        let first = try AccountCrypto.createAccount(email: "a@b.com", password: "pw", iterations: 1000)
        try await vaults.createInitialAccount(first.record)
        #expect(try await vaults.hasAccount() == true)

        let second = try AccountCrypto.createAccount(email: "evil@b.com", password: "pw2", iterations: 1000)
        await #expect(throws: VaultRepositoryError.self) {
            try await vaults.createInitialAccount(second.record)
        }
        // The original account survives untouched — no second row, key not orphaned.
        let surviving = try #require(try await vaults.account())
        #expect(surviving.id == first.record.accountID)
        #expect(surviving.encMasterKey == first.record.encMasterKey)
        #expect(try await database.writer.read { try AccountRecord.fetchCount($0) } == 1)
    }

    /// Even with no account row, leftover item rows (a partially-corrupted DB)
    /// must block a fresh account — those items are encrypted under the lost key.
    @Test func createInitialAccountRefusesOrphanItems() async throws {
        let database = try AppDatabase.inMemory()
        let vaults = VaultRepository(database: database, keyStore: KeyStore())
        try await database.writer.write { db in
            try VaultRecord(id: "v1", encVaultKey: Data([1]), encAttributes: Data([1]),
                            createdAt: Date(), syncState: "pending").insert(db)
            try ItemRecord(id: "i1", vaultId: "v1", encItemKey: Data([1]), encOverview: Data([1]),
                           encDetails: Data([1]), contentVersion: 1, createdAt: Date(), updatedAt: Date(),
                           trashedAt: nil, syncState: "pending", ckSystemFields: nil).insert(db)
        }
        // The orphan-items state the app routes to `.databaseError` (not onboarding).
        #expect(try await vaults.hasAccount() == false)
        #expect(try await vaults.hasItems() == true)

        let acct = try AccountCrypto.createAccount(email: "a@b.com", password: "pw", iterations: 1000)
        await #expect(throws: VaultRepositoryError.self) {
            try await vaults.createInitialAccount(acct.record)
        }
        #expect(try await vaults.hasAccount() == false)
    }

    @Test func itemCRUDRoundTrip() async throws {
        let env = try await TestEnvironment.make()
        let item = sampleLogin(vaultID: env.vault.id)
        try await env.items.create(item)

        let fetched = try #require(try await env.items.item(id: item.id))
        #expect(fetched.overview.title == "GitHub")
        #expect(fetched.details.firstField(withPurpose: .password)?.value == "hunter2")
        #expect(fetched.details.notes == "my note")

        var edited = fetched
        edited.overview.title = "GitHub Work"
        edited.details.sections[0].fields[1].value = "newpass"
        try await env.items.update(edited)

        let after = try #require(try await env.items.item(id: item.id))
        #expect(after.overview.title == "GitHub Work")
        #expect(after.details.firstField(withPurpose: .password)?.value == "newpass")

        let summaries = try await env.items.allSummaries()
        #expect(summaries.count == 1)
        #expect(summaries[0].overview.title == "GitHub Work")
    }

    @Test func historyVersioningAndRestore() async throws {
        let env = try await TestEnvironment.make()
        let item = sampleLogin(vaultID: env.vault.id)
        try await env.items.create(item)

        var v2 = try #require(try await env.items.item(id: item.id))
        v2.details.sections[0].fields[1].value = "secondpass"
        try await env.items.update(v2)

        var v3 = try #require(try await env.items.item(id: item.id))
        v3.details.sections[0].fields[1].value = "thirdpass"
        try await env.items.update(v3)

        let versions = try await env.items.versions(itemID: item.id)
        #expect(versions.count == 2)
        #expect(versions[0].details.firstField(withPurpose: .password)?.value == "secondpass")
        #expect(versions[1].details.firstField(withPurpose: .password)?.value == "hunter2")

        try await env.items.restoreVersion(versions[1], itemID: item.id)
        let restored = try #require(try await env.items.item(id: item.id))
        #expect(restored.details.firstField(withPurpose: .password)?.value == "hunter2")
        #expect(try await env.items.versions(itemID: item.id).count == 3)
    }

    @Test func trashFlow() async throws {
        let env = try await TestEnvironment.make()
        let item = sampleLogin(vaultID: env.vault.id)
        try await env.items.create(item)

        try await env.items.moveToTrash(itemID: item.id)
        var fetched = try #require(try await env.items.item(id: item.id))
        #expect(fetched.trashedAt != nil)

        try await env.items.restoreFromTrash(itemID: item.id)
        fetched = try #require(try await env.items.item(id: item.id))
        #expect(fetched.trashedAt == nil)

        try await env.items.moveToTrash(itemID: item.id)
        try await env.items.emptyTrash()
        #expect(try await env.items.item(id: item.id) == nil)
    }

    @Test func moveBetweenVaults() async throws {
        let env = try await TestEnvironment.make()
        let work = try await env.vaults.createVault(attributes: VaultAttributes(name: "Work"))
        let item = sampleLogin(vaultID: env.vault.id)
        try await env.items.create(item)

        try await env.items.move(itemID: item.id, toVault: work.id)
        let moved = try #require(try await env.items.item(id: item.id))
        #expect(moved.vaultID == work.id)
        #expect(moved.details.firstField(withPurpose: .password)?.value == "hunter2")
    }

    @Test("all 22 category templates encrypt and decrypt intact")
    func templatesRoundTrip() async throws {
        let env = try await TestEnvironment.make()
        for category in Category.allCases {
            var item = VaultItem(vaultID: env.vault.id)
            item.overview = ItemOverview(title: category.displayName, category: category)
            item.details = ItemDetails(sections: CategoryTemplates.template(for: category))
            try await env.items.create(item)
            let fetched = try #require(try await env.items.item(id: item.id))
            #expect(fetched.details.sections == item.details.sections)
            #expect(fetched.overview.category == category)
        }
        #expect(try await env.items.allSummaries().count == Category.allCases.count)
    }

    @Test func lockedReadsFail() async throws {
        let env = try await TestEnvironment.make()
        let item = sampleLogin(vaultID: env.vault.id)
        try await env.items.create(item)
        await env.keyStore.lock()
        await #expect(throws: CryptoError.self) {
            _ = try await env.items.item(id: item.id)
        }
    }
}
