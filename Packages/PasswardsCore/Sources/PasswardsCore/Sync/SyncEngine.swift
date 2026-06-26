import Foundation
import CloudKit
import CryptoKit
import GRDB
import os

/// CloudKit sync over `CKSyncEngine`. Only ciphertext crosses the wire:
/// records carry the same encrypted blobs stored locally, in one custom zone.
/// Conflicts resolve last-writer-wins by `updatedAt`; a losing item payload is
/// preserved as a local history version so no edit is ever silently lost.
public actor SyncEngine {
    public static let zoneName = "Main"
    static let stateKey = "ckStateSerialization"
    static let log = Logger(subsystem: "com.michael.passwards", category: "sync")

    public enum Status: Sendable, Equatable {
        case idle
        case syncing
        case error(String)
        case accountUnavailable
    }

    let database: AppDatabase
    let containerIdentifier: String
    var engine: CKSyncEngine?
    public private(set) var status: Status = .idle
    var onStatusChange: (@Sendable (Status) -> Void)?

    /// Records that failed to apply because a parent row hasn't arrived yet
    /// (e.g. item before its vault); retried after each fetch completes.
    var deferredRecords: [CKRecord] = []

    var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: Self.zoneName) }

    public init(database: AppDatabase, containerIdentifier: String) {
        self.database = database
        self.containerIdentifier = containerIdentifier
    }

    public func setStatusHandler(_ handler: @Sendable @escaping (Status) -> Void) {
        onStatusChange = handler
    }

    private func setStatus(_ new: Status) {
        status = new
        onStatusChange?(new)
    }

    // MARK: Lifecycle

    public func start() async {
        guard engine == nil else { return }
        Self.log.info("starting CKSyncEngine for container \(self.containerIdentifier, privacy: .public)")
        var state: CKSyncEngine.State.Serialization?
        if let data = try? await database.syncMetaValue(key: Self.stateKey) {
            state = try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
        }
        let container = CKContainer(identifier: containerIdentifier)
        let configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: state,
            delegate: self
        )
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        await enqueuePendingChanges()
    }

    public func stop() {
        engine = nil
    }

    public func manualSync() async {
        guard let engine else { return }
        do {
            try await engine.sendChanges()
            try await engine.fetchChanges()
            setStatus(.idle)
        } catch {
            Self.log.error("manualSync failed: \(String(describing: error), privacy: .public)")
            setStatus(.error(error.localizedDescription))
        }
    }

    /// Scans for locally pending rows and tombstones and queues them.
    public func enqueuePendingChanges() async {
        guard let engine else { return }
        do {
            let (hasAccount, vaultIDs, itemIDs, attachmentIDs, tombstones) = try await database.writer.read { db in
                (
                    try AccountRecord.fetchCount(db) > 0,
                    try String.fetchAll(db, sql: "SELECT id FROM vault WHERE syncState = 'pending'"),
                    try String.fetchAll(db, sql: "SELECT id FROM item WHERE syncState = 'pending'"),
                    try String.fetchAll(db, sql: "SELECT id FROM attachment WHERE syncState = 'pending'"),
                    try String.fetchAll(db, sql: "SELECT recordName FROM tombstone")
                )
            }
            var changes: [CKSyncEngine.PendingRecordZoneChange] = []
            // Only push the account when it actually changed (vs every sync), so a
            // signed-in device whose account matches the server doesn't churn.
            if hasAccount, await accountNeedsPush() {
                changes.append(.saveRecord(recordID("account")))
            }
            changes += vaultIDs.map { .saveRecord(recordID("vault-\($0)")) }
            changes += itemIDs.map { .saveRecord(recordID("item-\($0)")) }
            changes += attachmentIDs.map { .saveRecord(recordID("attach-\($0)")) }
            changes += tombstones.map { .deleteRecord(recordID($0)) }
            if !changes.isEmpty {
                engine.state.add(pendingRecordZoneChanges: changes)
            }
        } catch {
            setStatus(.error(error.localizedDescription))
        }
    }

    func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zoneID)
    }

    // MARK: Account record sync-state (etag + content hash)
    //
    // The account row has no `syncState`/`ckSystemFields` column, so its CloudKit
    // system fields (etag) and last-pushed content hash live in `syncMeta` (no
    // migration). The hash lets us push the account ONLY when it actually changes
    // — a freshly-signed-in device's account already matches the server, so it
    // never re-pushes (which previously failed forever with "record already
    // exists"). The etag lets a genuine change UPDATE instead of INSERT.

    private static let accountSystemFieldsKey = "accountSystemFields"
    private static let accountPushedHashKey = "accountPushedHash"

    private func currentAccountHash() async -> Data? {
        guard let account = try? await database.writer.read({ try AccountRecord.fetchOne($0) }) else { return nil }
        var hasher = SHA256()
        hasher.update(data: Data(account.id.utf8))
        hasher.update(data: Data(account.email.utf8))
        hasher.update(data: account.kdfSalt)
        hasher.update(data: Data(String(account.kdfIterations).utf8))
        hasher.update(data: account.encMasterKey)
        hasher.update(data: Data([account.recoveryEnabled ? 1 : 0]))
        if let blob = account.recoveryBlob { hasher.update(data: blob) }
        if let code = account.encRecoveryCode { hasher.update(data: code) }
        return Data(hasher.finalize())
    }

    private func accountNeedsPush() async -> Bool {
        guard let current = await currentAccountHash() else { return false }
        let pushed = (try? await database.syncMetaValue(key: Self.accountPushedHashKey)) ?? nil
        return current != pushed
    }

    private func accountBaseRecord() async -> CKRecord? {
        guard let data = (try? await database.syncMetaValue(key: Self.accountSystemFieldsKey)) ?? nil else { return nil }
        return RecordCoder.unarchiveSystemFields(data)
    }

    /// Marks the local account as matching CloudKit: stores the record's system
    /// fields (etag, for the next UPDATE) and the content hash (so we don't push
    /// again until the account actually changes).
    private func noteAccountSynced(systemFields record: CKRecord) async {
        try? await database.setSyncMetaValue(RecordCoder.archiveSystemFields(record), key: Self.accountSystemFieldsKey)
        if let hash = await currentAccountHash() {
            try? await database.setSyncMetaValue(hash, key: Self.accountPushedHashKey)
        }
    }

    // MARK: New-device bootstrap

    /// Fetches the account key record directly (no sync engine), for the
    /// "sign in to existing account" flow on a fresh machine.
    public static func fetchRemoteAccount(containerIdentifier: String) async throws -> AccountCrypto.AccountKeyRecord? {
        let container = CKContainer(identifier: containerIdentifier)
        let db = container.privateCloudDatabase
        let id = CKRecord.ID(recordName: "account", zoneID: CKRecordZone.ID(zoneName: zoneName))
        do {
            let record = try await db.record(for: id)
            return RecordCoder.accountKeyRecord(from: record)
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        }
    }
}

// MARK: - CKSyncEngineDelegate

extension SyncEngine: CKSyncEngineDelegate {
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let stateUpdate):
            if let data = try? JSONEncoder().encode(stateUpdate.stateSerialization) {
                try? await database.setSyncMetaValue(data, key: Self.stateKey)
            }

        case .accountChange(let change):
            switch change.changeType {
            case .signIn:
                setStatus(.idle)
                await enqueuePendingChanges()
            case .signOut, .switchAccounts:
                setStatus(.accountUnavailable)
            @unknown default:
                break
            }

        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions where deletion.zoneID == zoneID {
                // Zone removed remotely: re-create and re-push everything.
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                try? await database.writer.write { db in
                    try db.execute(sql: "UPDATE vault SET syncState = 'pending'")
                    try db.execute(sql: "UPDATE item SET syncState = 'pending'")
                    try db.execute(sql: "UPDATE attachment SET syncState = 'pending'")
                }
                await enqueuePendingChanges()
            }

        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications {
                await applyRemoteRecord(modification.record)
            }
            for deletion in changes.deletions {
                await applyRemoteDeletion(deletion.recordID)
            }

        case .sentRecordZoneChanges(let sent):
            Self.log.info("sent: \(sent.savedRecords.count) saved, \(sent.failedRecordSaves.count) failed, \(sent.deletedRecordIDs.count) deleted")
            for save in sent.savedRecords {
                if save.recordID.recordName == "account" {
                    await noteAccountSynced(systemFields: save)
                }
                await markSynced(recordName: save.recordID.recordName)
            }
            for deletion in sent.deletedRecordIDs {
                try? await database.writer.write { db in
                    try db.execute(sql: "DELETE FROM tombstone WHERE recordName = ?", arguments: [deletion.recordName])
                }
            }
            for failure in sent.failedRecordSaves {
                await handleSaveFailure(failure, syncEngine: syncEngine)
            }

        case .willSendChanges, .willFetchChanges:
            setStatus(.syncing)

        case .didSendChanges:
            setStatus(.idle)

        case .didFetchChanges:
            // Retry records deferred on missing parents, until stable.
            var passes = 0
            while !deferredRecords.isEmpty && passes < 3 {
                let batch = deferredRecords
                deferredRecords = []
                for record in batch {
                    await applyRemoteRecord(record)
                }
                passes += 1
            }
            deferredRecords = []
            setStatus(.idle)

        default:
            break
        }
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { [weak self] recordID in
            await self?.buildRecord(recordName: recordID.recordName)
        }
    }

    // MARK: Building outgoing records

    func buildRecord(recordName: String) async -> CKRecord? {
        do {
            if recordName == "account" {
                guard let account = try await database.writer.read({ try AccountRecord.fetchOne($0) }) else { return nil }
                return RecordCoder.record(for: account, recordID: recordID(recordName), baseRecord: await accountBaseRecord())
            }
            if let id = recordName.dropPrefixOrNil("vault-") {
                guard let vault = try await database.writer.read({ try VaultRecord.fetchOne($0, key: id) }) else { return nil }
                return RecordCoder.record(for: vault, recordID: recordID(recordName))
            }
            if let id = recordName.dropPrefixOrNil("item-") {
                guard let item = try await database.writer.read({ try ItemRecord.fetchOne($0, key: id) }) else { return nil }
                return RecordCoder.record(for: item, recordID: recordID(recordName), baseRecord: archivedRecord(item.ckSystemFields))
            }
            if let id = recordName.dropPrefixOrNil("attach-") {
                guard let attachment = try await database.writer.read({ try AttachmentRecord.fetchOne($0, key: id) }) else { return nil }
                let fileURL = try attachmentFileURL(id)
                return RecordCoder.record(for: attachment, recordID: recordID(recordName), fileURL: fileURL)
            }
        } catch {
            setStatus(.error(error.localizedDescription))
        }
        return nil
    }

    private func attachmentFileURL(_ id: String) throws -> URL {
        // Defense in depth: `id` ultimately comes from a CloudKit recordName.
        // Require a canonical UUID (no `/`, no `..`) and verify the resolved
        // path stays inside the Attachments directory before any file op.
        guard UUID(uuidString: id) != nil else { throw AttachmentPathError.invalidID }
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )
        let directory = appSupport.appendingPathComponent("2Password/Attachments", isDirectory: true)
        let destination = directory.appendingPathComponent(id)
        guard destination.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path + "/") else {
            throw AttachmentPathError.invalidID
        }
        return destination
    }

    private func archivedRecord(_ data: Data?) -> CKRecord? {
        guard let data else { return nil }
        return RecordCoder.unarchiveSystemFields(data)
    }

    // MARK: Applying incoming records

    func applyRemoteRecord(_ record: CKRecord) async {
        do {
            switch record.recordType {
            case "Account":
                guard let incoming = RecordCoder.accountKeyRecord(from: record) else { return }
                // Adopt on bootstrap, or a password change that re-wrapped the
                // master key. The prior key material is backed up first so an
                // unauthenticated/rolled-back record can't lock the user out.
                try await database.adoptRemoteAccount(incoming)
                // Remember the server's etag + that we now match it, so we don't
                // try to re-insert this account record.
                await noteAccountSynced(systemFields: record)

            case "Vault":
                guard let vault = RecordCoder.vaultRecord(from: record) else { return }
                try await database.writer.write { db in
                    try vault.save(db)
                }

            case "Item":
                guard let incoming = RecordCoder.itemRecord(from: record) else { return }
                let systemFields = RecordCoder.archiveSystemFields(record)
                try await database.writer.write { db in
                    if let local = try ItemRecord.fetchOne(db, key: incoming.id) {
                        if local.syncState == "pending" && local.updatedAt > incoming.updatedAt {
                            // Local wins; remote payload preserved as history.
                            var version = ItemVersionRecord(
                                id: nil,
                                itemId: incoming.id,
                                versionNumber: incoming.contentVersion,
                                encOverview: incoming.encOverview,
                                encDetails: incoming.encDetails,
                                editedAt: incoming.updatedAt
                            )
                            try version.insert(db)
                            // Keep local pending so it pushes over the top.
                            try db.execute(
                                sql: "UPDATE item SET ckSystemFields = ? WHERE id = ?",
                                arguments: [systemFields, incoming.id]
                            )
                        } else {
                            if local.encDetails != incoming.encDetails {
                                var version = ItemVersionRecord(
                                    id: nil,
                                    itemId: local.id,
                                    versionNumber: local.contentVersion,
                                    encOverview: local.encOverview,
                                    encDetails: local.encDetails,
                                    editedAt: local.updatedAt
                                )
                                try version.insert(db)
                            }
                            var updated = incoming
                            updated.syncState = "synced"
                            updated.ckSystemFields = systemFields
                            try updated.save(db)
                        }
                    } else {
                        var new = incoming
                        new.syncState = "synced"
                        new.ckSystemFields = systemFields
                        try new.insert(db)
                    }
                }

            case "Attachment":
                guard let attachment = RecordCoder.attachmentRecord(from: record) else { return }
                if let asset = record["asset"] as? CKAsset, let sourceURL = asset.fileURL {
                    let dest = try attachmentFileURL(attachment.id)
                    try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: dest.path) {
                        try FileManager.default.removeItem(at: dest)
                    }
                    try FileManager.default.copyItem(at: sourceURL, to: dest)
                }
                try await database.writer.write { db in
                    var record = attachment
                    record.syncState = "synced"
                    try record.save(db)
                }

            default:
                break
            }
        } catch let dbError as DatabaseError where dbError.resultCode == .SQLITE_CONSTRAINT {
            deferredRecords.append(record)
        } catch {
            setStatus(.error(error.localizedDescription))
        }
    }

    func applyRemoteDeletion(_ recordID: CKRecord.ID) async {
        let name = recordID.recordName
        try? await database.writer.write { db in
            if let id = name.dropPrefixOrNil("item-") {
                _ = try ItemRecord.deleteOne(db, key: id)
            } else if let id = name.dropPrefixOrNil("vault-") {
                _ = try VaultRecord.deleteOne(db, key: id)
            } else if let id = name.dropPrefixOrNil("attach-") {
                _ = try AttachmentRecord.deleteOne(db, key: id)
            }
        }
    }

    func markSynced(recordName: String) async {
        try? await database.writer.write { db in
            if let id = recordName.dropPrefixOrNil("item-") {
                try db.execute(sql: "UPDATE item SET syncState = 'synced' WHERE id = ? AND syncState = 'pending'", arguments: [id])
            } else if let id = recordName.dropPrefixOrNil("vault-") {
                try db.execute(sql: "UPDATE vault SET syncState = 'synced' WHERE id = ?", arguments: [id])
            } else if let id = recordName.dropPrefixOrNil("attach-") {
                try db.execute(sql: "UPDATE attachment SET syncState = 'synced' WHERE id = ?", arguments: [id])
            }
        }
    }

    func handleSaveFailure(_ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave, syncEngine: CKSyncEngine) async {
        Self.log.error("save failed [\(failure.record.recordType, privacy: .public) \(failure.record.recordID.recordName, privacy: .public)] code=\(failure.error.code.rawValue): \(String(describing: failure.error), privacy: .public)")
        switch failure.error.code {
        case .serverRecordChanged:
            guard let serverRecord = failure.error.serverRecord else { return }
            // Re-apply LWW against the server copy, then retry on top of it.
            await applyRemoteRecord(serverRecord)
            if failure.record.recordType == "Item",
               let id = failure.record.recordID.recordName.dropPrefixOrNil("item-") {
                let stillPending = (try? await database.writer.read { db in
                    try String.fetchOne(db, sql: "SELECT syncState FROM item WHERE id = ?", arguments: [id])
                }) == "pending"
                if stillPending {
                    try? await database.writer.write { db in
                        try db.execute(
                            sql: "UPDATE item SET ckSystemFields = ? WHERE id = ?",
                            arguments: [RecordCoder.archiveSystemFields(serverRecord), id]
                        )
                    }
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(failure.record.recordID)])
                }
            } else {
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(failure.record.recordID)])
            }

        case .zoneNotFound:
            syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(failure.record.recordID)])

        case .unknownItem:
            // Record deleted server-side while we tried to update it; re-create.
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(failure.record.recordID)])

        default:
            setStatus(.error(failure.error.localizedDescription))
        }
    }
}

extension String {
    func dropPrefixOrNil(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}

/// Thrown when an attachment id (from a CloudKit recordName) is not a canonical
/// UUID or would resolve outside the Attachments directory.
private enum AttachmentPathError: Error { case invalidID }
