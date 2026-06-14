import Testing
import Foundation
import CloudKit
@testable import TwoPasswordCore

@Suite("Sync record coding")
struct RecordCoderTests {
    private let zoneID = CKRecordZone.ID(zoneName: SyncEngine.zoneName)

    @Test func accountRoundTrip() throws {
        let original = AccountRecord(
            id: "ABC234",
            email: "m@example.com",
            kdfSalt: Data(repeating: 1, count: 16),
            kdfIterations: 650_000,
            encMasterKey: Data(repeating: 2, count: 60),
            createdAt: Date()
        )
        let record = RecordCoder.record(for: original, recordID: CKRecord.ID(recordName: "account", zoneID: zoneID))
        let decoded = try #require(RecordCoder.accountKeyRecord(from: record))
        #expect(decoded.accountID == original.id)
        #expect(decoded.email == original.email)
        #expect(decoded.kdfSalt == original.kdfSalt)
        #expect(decoded.kdfIterations == original.kdfIterations)
        #expect(decoded.encMasterKey == original.encMasterKey)
    }

    @Test func vaultRoundTrip() throws {
        let original = VaultRecord(
            id: "v-1",
            encVaultKey: Data(repeating: 3, count: 60),
            encAttributes: Data(repeating: 4, count: 80),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            syncState: "pending"
        )
        let record = RecordCoder.record(for: original, recordID: CKRecord.ID(recordName: "vault-v-1", zoneID: zoneID))
        let decoded = try #require(RecordCoder.vaultRecord(from: record))
        #expect(decoded.id == original.id)
        #expect(decoded.encVaultKey == original.encVaultKey)
        #expect(decoded.encAttributes == original.encAttributes)
        #expect(decoded.syncState == "synced")
    }

    @Test func itemRoundTrip() throws {
        let original = ItemRecord(
            id: "i-1",
            vaultId: "v-1",
            encItemKey: Data(repeating: 5, count: 60),
            encOverview: Data(repeating: 6, count: 120),
            encDetails: Data(repeating: 7, count: 200),
            contentVersion: 7,
            createdAt: Date(timeIntervalSince1970: 1_600_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            trashedAt: Date(timeIntervalSince1970: 1_710_000_000),
            syncState: "pending",
            ckSystemFields: nil
        )
        let record = RecordCoder.record(for: original, recordID: CKRecord.ID(recordName: "item-i-1", zoneID: zoneID), baseRecord: nil)
        let decoded = try #require(RecordCoder.itemRecord(from: record))
        #expect(decoded.id == original.id)
        #expect(decoded.vaultId == original.vaultId)
        #expect(decoded.encItemKey == original.encItemKey)
        #expect(decoded.encOverview == original.encOverview)
        #expect(decoded.encDetails == original.encDetails)
        #expect(decoded.contentVersion == 7)
        #expect(decoded.trashedAt == original.trashedAt)
    }

    @Test("record payloads contain no plaintext item data")
    func noPlaintextLeaks() async throws {
        // Build a real encrypted item and verify the CKRecord carries only
        // ciphertext: the password must not appear anywhere in the record.
        let env = try await TestEnvironment.make()
        var item = VaultItem(vaultID: env.vault.id)
        item.overview = ItemOverview(title: "SuperSecretSite", category: .login)
        item.details = ItemDetails(sections: [ItemSection(fields: [
            ItemField(label: "password", kind: .concealed, value: "hunter2-plaintext", purpose: .password)
        ])])
        try await env.items.create(item)

        let itemID = item.id
        let row = try await env.database.writer.read { try ItemRecord.fetchOne($0, key: itemID)! }
        let record = RecordCoder.record(for: row, recordID: CKRecord.ID(recordName: "item-\(item.id)", zoneID: zoneID), baseRecord: nil)

        for key in record.allKeys() {
            if let data = record[key] as? Data {
                #expect(!String(decoding: data, as: UTF8.self).contains("hunter2"))
                #expect(!String(decoding: data, as: UTF8.self).contains("SuperSecretSite"))
            }
            if let string = record[key] as? String {
                #expect(!string.contains("hunter2"))
                #expect(!string.contains("SuperSecretSite"))
            }
        }
    }

    @Test func attachmentRecordRejectsPathTraversalID() {
        // A remote attachment's id is used to build an on-disk write path, so a
        // malicious/foreign CloudKit recordName must NOT decode into a record.
        func decode(_ recordName: String) -> AttachmentRecord? {
            let record = CKRecord(recordType: "Attachment",
                                  recordID: CKRecord.ID(recordName: recordName, zoneID: zoneID))
            record["itemId"] = "item-1"
            record["encMetadata"] = Data([1, 2, 3])
            return RecordCoder.attachmentRecord(from: record)
        }
        // Traversal / non-canonical ids are rejected.
        #expect(decode("attach-../../../../tmp/evil") == nil)
        #expect(decode("attach-..") == nil)
        #expect(decode("attach-not-a-uuid") == nil)
        #expect(decode("attach-") == nil)
        // A canonical UUID is accepted and preserved.
        let id = UUID().uuidString
        let valid = decode("attach-\(id)")
        #expect(valid?.id == id)
    }

    @Test func systemFieldsArchiving() throws {
        let record = CKRecord(recordType: "Item", recordID: CKRecord.ID(recordName: "item-x", zoneID: zoneID))
        let archived = RecordCoder.archiveSystemFields(record)
        let unarchived = try #require(RecordCoder.unarchiveSystemFields(archived))
        #expect(unarchived.recordID.recordName == "item-x")
        #expect(unarchived.recordType == "Item")
    }
}
