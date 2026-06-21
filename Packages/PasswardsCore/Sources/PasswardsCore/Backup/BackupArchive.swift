import Foundation
import CryptoKit

/// A portable encrypted backup of the whole vault.
///
/// The file is a JSON envelope: a readable HEADER (the account row — KDF params,
/// `encMasterKey`, and the recovery material) plus a PAYLOAD (`BackupContents`)
/// AES-256-GCM-sealed under the master key. Opening it reuses the normal unlock
/// path against the header — `AccountCrypto.unlock` (password + Secret Key) or
/// `AccountCrypto.recover` (recovery code) → master key → open payload. So the
/// backup is exactly as confidential as the live vault, and needs no new crypto.
public struct BackupContents: Codable, Sendable {
    public var vaults: [VaultRecord]
    public var items: [ItemRecord]
    public var itemVersions: [ItemVersionRecord]
    public var attachments: [AttachmentRecord]
    /// Attachment ciphertext bytes keyed by attachment ID (already encrypted on disk).
    public var attachmentFiles: [String: Data]

    public init(
        vaults: [VaultRecord], items: [ItemRecord], itemVersions: [ItemVersionRecord],
        attachments: [AttachmentRecord], attachmentFiles: [String: Data]
    ) {
        self.vaults = vaults
        self.items = items
        self.itemVersions = itemVersions
        self.attachments = attachments
        self.attachmentFiles = attachmentFiles
    }
}

public struct BackupFile: Codable, Sendable {
    public var version: Int
    public var createdAt: Date
    /// Header: everything needed to recover the master key (no secrets in the clear).
    public var account: AccountRecord
    /// `BackupContents` sealed under the master key, AAD = "backup:<accountID>".
    public var sealedContents: Data
}

public enum BackupError: Error, Sendable {
    case unreadable
    case unsupportedVersion(Int)
}

public enum BackupArchive {
    public static let fileExtension = "pwbackup"
    public static let formatVersion = 1

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Seals the contents under the master key and encodes the whole backup file.
    ///
    /// With `includeRecovery: false` the recovery escrow is stripped from the
    /// header (a "password-only" backup): the exported file can then only be
    /// opened with the account password + Secret Key, never a recovery code.
    /// This is the way to make a backup that a code rotation actually "covers" —
    /// a recovery code opens any backup made while it was active, even after the
    /// user disables/rotates it, because rotation can't reach already-exported
    /// files.
    public static func encode(
        account: AccountRecord,
        contents: BackupContents,
        masterKey: SymmetricKey,
        createdAt: Date,
        includeRecovery: Bool = true
    ) throws -> Data {
        var header = account
        if !includeRecovery {
            header.recoveryEnabled = false
            header.recoveryBlob = nil
            header.encRecoveryCode = nil
        }
        let sealed = try EncryptedBlob.seal(
            encoder().encode(contents), key: masterKey, aad: "backup:\(header.id)"
        )
        let file = BackupFile(version: formatVersion, createdAt: createdAt, account: header, sealedContents: sealed)
        return try encoder().encode(file)
    }

    /// Decodes the envelope. The header (account email, recovery state) is readable
    /// without any key; the payload stays sealed. Throws on a corrupt or
    /// newer-than-supported file.
    public static func decode(_ data: Data) throws -> BackupFile {
        let file: BackupFile
        do {
            file = try decoder().decode(BackupFile.self, from: data)
        } catch {
            throw BackupError.unreadable
        }
        guard file.version <= formatVersion else { throw BackupError.unsupportedVersion(file.version) }
        return file
    }

    /// Opens the sealed payload with the recovered master key.
    public static func openContents(_ file: BackupFile, masterKey: SymmetricKey) throws -> BackupContents {
        let plaintext = try EncryptedBlob.open(file.sealedContents, key: masterKey, aad: "backup:\(file.account.id)")
        return try decoder().decode(BackupContents.self, from: plaintext)
    }
}
