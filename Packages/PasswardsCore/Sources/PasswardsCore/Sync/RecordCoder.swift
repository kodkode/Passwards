import Foundation
import CloudKit

/// Maps between local rows and CKRecords. Every payload field is ciphertext;
/// the only plaintext is identifiers, timestamps, and sizes.
public enum RecordCoder {
    // MARK: Account

    static func record(for account: AccountRecord, recordID: CKRecord.ID) -> CKRecord {
        let record = CKRecord(recordType: "Account", recordID: recordID)
        record["accountID"] = account.id
        record["email"] = account.email
        record["kdfSalt"] = account.kdfSalt
        record["kdfIterations"] = account.kdfIterations
        record["encMasterKey"] = account.encMasterKey
        // Always set the flag so on/off propagates; blobs are set whenever present
        // (turning recovery off overwrites them with random bytes, not nil, so a
        // fresh CKRecord can still overwrite the stale server copy).
        record["recoveryEnabled"] = account.recoveryEnabled ? 1 : 0
        if let recoveryBlob = account.recoveryBlob { record["recoveryBlob"] = recoveryBlob }
        if let encRecoveryCode = account.encRecoveryCode { record["encRecoveryCode"] = encRecoveryCode }
        return record
    }

    public static func accountKeyRecord(from record: CKRecord) -> AccountCrypto.AccountKeyRecord? {
        guard let accountID = record["accountID"] as? String,
              let email = record["email"] as? String,
              let kdfSalt = record["kdfSalt"] as? Data,
              let kdfIterations = record["kdfIterations"] as? Int,
              let encMasterKey = record["encMasterKey"] as? Data else { return nil }
        return .init(
            accountID: accountID, email: email, kdfSalt: kdfSalt, kdfIterations: kdfIterations,
            encMasterKey: encMasterKey,
            recoveryEnabled: (record["recoveryEnabled"] as? Int ?? 0) == 1,
            recoveryBlob: record["recoveryBlob"] as? Data,
            encRecoveryCode: record["encRecoveryCode"] as? Data
        )
    }

    // MARK: Vault

    static func record(for vault: VaultRecord, recordID: CKRecord.ID) -> CKRecord {
        let record = CKRecord(recordType: "Vault", recordID: recordID)
        record["encVaultKey"] = vault.encVaultKey
        record["encAttributes"] = vault.encAttributes
        record["createdAt"] = vault.createdAt
        return record
    }

    static func vaultRecord(from record: CKRecord) -> VaultRecord? {
        guard let id = record.recordID.recordName.dropPrefixOrNil("vault-"),
              let encVaultKey = record["encVaultKey"] as? Data,
              let encAttributes = record["encAttributes"] as? Data else { return nil }
        return VaultRecord(
            id: id,
            encVaultKey: encVaultKey,
            encAttributes: encAttributes,
            createdAt: record["createdAt"] as? Date ?? Date(),
            syncState: "synced"
        )
    }

    // MARK: Item

    static func record(for item: ItemRecord, recordID: CKRecord.ID, baseRecord: CKRecord?) -> CKRecord {
        let record = baseRecord ?? CKRecord(recordType: "Item", recordID: recordID)
        record["vaultId"] = item.vaultId
        record["encItemKey"] = item.encItemKey
        record["encOverview"] = item.encOverview
        record["encDetails"] = item.encDetails
        record["contentVersion"] = item.contentVersion
        record["createdAt"] = item.createdAt
        record["updatedAt"] = item.updatedAt
        record["trashedAt"] = item.trashedAt
        return record
    }

    static func itemRecord(from record: CKRecord) -> ItemRecord? {
        guard let id = record.recordID.recordName.dropPrefixOrNil("item-"),
              let vaultId = record["vaultId"] as? String,
              let encItemKey = record["encItemKey"] as? Data,
              let encOverview = record["encOverview"] as? Data,
              let encDetails = record["encDetails"] as? Data else { return nil }
        return ItemRecord(
            id: id,
            vaultId: vaultId,
            encItemKey: encItemKey,
            encOverview: encOverview,
            encDetails: encDetails,
            contentVersion: record["contentVersion"] as? Int ?? 1,
            createdAt: record["createdAt"] as? Date ?? Date(),
            updatedAt: record["updatedAt"] as? Date ?? Date(),
            trashedAt: record["trashedAt"] as? Date,
            syncState: "synced",
            ckSystemFields: nil
        )
    }

    public static func archiveSystemFields(_ record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    public static func unarchiveSystemFields(_ data: Data) -> CKRecord? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        return CKRecord(coder: unarchiver)
    }

    // MARK: Attachment

    static func record(for attachment: AttachmentRecord, recordID: CKRecord.ID, fileURL: URL) -> CKRecord {
        let record = CKRecord(recordType: "Attachment", recordID: recordID)
        record["itemId"] = attachment.itemId
        record["encMetadata"] = attachment.encMetadata
        record["fileSize"] = attachment.fileSize
        if FileManager.default.fileExists(atPath: fileURL.path) {
            record["asset"] = CKAsset(fileURL: fileURL)
        }
        return record
    }

    static func attachmentRecord(from record: CKRecord) -> AttachmentRecord? {
        guard let id = record.recordID.recordName.dropPrefixOrNil("attach-"),
              // The id is used to build an on-disk path, and the recordName is
              // attacker-influenceable (a compromised/foreign CloudKit record).
              // Require a canonical UUID so it can carry no `/` or `..` and
              // cannot escape the Attachments directory.
              UUID(uuidString: id) != nil,
              let itemId = record["itemId"] as? String,
              let encMetadata = record["encMetadata"] as? Data else { return nil }
        return AttachmentRecord(
            id: id,
            itemId: itemId,
            encMetadata: encMetadata,
            fileSize: record["fileSize"] as? Int ?? 0,
            syncState: "synced"
        )
    }
}
