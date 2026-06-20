import Foundation
import CryptoKit
import GRDB

public struct AttachmentMetadata: Codable, Sendable, Equatable {
    public var filename: String
    public var size: Int

    public init(filename: String, size: Int) {
        self.filename = filename
        self.size = size
    }
}

/// Encrypted file attachments: ciphertext files on disk keyed by attachment ID,
/// metadata sealed in the database, both under the owning item's key.
public struct AttachmentStore: Sendable {
    public static let maxFileSize = 25 * 1024 * 1024

    let database: AppDatabase
    let keyStore: KeyStore
    public let directory: URL

    public init(database: AppDatabase, keyStore: KeyStore, directory: URL? = nil) throws {
        self.database = database
        self.keyStore = keyStore
        if let directory {
            self.directory = directory
        } else {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            self.directory = appSupport.appendingPathComponent("2Password/Attachments", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    public enum AttachmentError: Error {
        case fileTooLarge
        case notFound
    }

    private func itemKey(itemID: String) async throws -> SymmetricKey {
        guard let itemRecord = try await database.writer.read({ db in
            try ItemRecord.fetchOne(db, key: itemID)
        }), let vaultRecord = try await database.writer.read({ db in
            try VaultRecord.fetchOne(db, key: itemRecord.vaultId)
        }) else { throw CryptoError.decryptionFailed }
        return try await keyStore.itemKey(
            itemID: itemID,
            encItemKey: itemRecord.encItemKey,
            vaultID: itemRecord.vaultId,
            encVaultKey: vaultRecord.encVaultKey
        )
    }

    /// Encrypts and stores file data; returns the attachment ID to put in a
    /// `.file` field.
    @discardableResult
    public func add(data: Data, filename: String, itemID: String) async throws -> String {
        guard data.count <= Self.maxFileSize else { throw AttachmentError.fileTooLarge }
        let key = try await itemKey(itemID: itemID)
        let attachmentID = UUID().uuidString
        let ciphertext = try EncryptedBlob.seal(data, key: key, aad: "attachfile:\(attachmentID)")
        let metadata = AttachmentMetadata(filename: filename, size: data.count)
        let encMetadata = try EncryptedBlob.seal(metadata, key: key, aad: "attachmeta:\(attachmentID)")

        try ciphertext.write(to: fileURL(attachmentID), options: .atomic)
        let record = AttachmentRecord(
            id: attachmentID,
            itemId: itemID,
            encMetadata: encMetadata,
            fileSize: data.count,
            syncState: "pending"
        )
        try await database.writer.write { db in
            try record.insert(db)
        }
        return attachmentID
    }

    public func metadata(attachmentID: String) async throws -> AttachmentMetadata {
        guard let record = try await database.writer.read({ db in
            try AttachmentRecord.fetchOne(db, key: attachmentID)
        }) else { throw AttachmentError.notFound }
        let key = try await itemKey(itemID: record.itemId)
        return try EncryptedBlob.open(AttachmentMetadata.self, from: record.encMetadata, key: key, aad: "attachmeta:\(attachmentID)")
    }

    public func decrypt(attachmentID: String) async throws -> Data {
        guard let record = try await database.writer.read({ db in
            try AttachmentRecord.fetchOne(db, key: attachmentID)
        }) else { throw AttachmentError.notFound }
        let key = try await itemKey(itemID: record.itemId)
        let ciphertext = try Data(contentsOf: fileURL(attachmentID))
        return try EncryptedBlob.open(ciphertext, key: key, aad: "attachfile:\(attachmentID)")
    }

    public func delete(attachmentID: String) async throws {
        try? FileManager.default.removeItem(at: fileURL(attachmentID))
        _ = try await database.writer.write { db in
            try AttachmentRecord.deleteOne(db, key: attachmentID)
        }
    }

    /// Removes ciphertext files whose DB rows are gone (e.g. item deleted).
    public func collectGarbage() async throws {
        let validIDs = Set(try await database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM attachment")
        })
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where !validIDs.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    public func fileURL(_ attachmentID: String) -> URL {
        directory.appendingPathComponent(attachmentID)
    }
}
