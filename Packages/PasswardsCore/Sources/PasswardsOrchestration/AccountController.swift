import CryptoKit
import Foundation
import Observation
import PasswardsCore

public enum AppPhase: Equatable {
    case loading
    case onboarding
    case databaseError
    case locked
    case unlocked
}

/// Cross-platform root state machine: onboarding → locked ⇄ unlocked. Owns the
/// database, key store, and repositories; both apps' UI hangs off it.
///
/// Platform behavior is injected so this stays AppKit/UIKit-free:
/// - `autoLock` / `pasteboard` are the platform-service seams.
/// - `onVaultShouldClearSecrets` / `onVaultShouldRefresh` are wired by each app
///   to its vault view-model (the decrypted-overview cache lives there).
/// - `appGroupIdentifier` is nil on macOS (Application Support, byte-identical to
///   before) and the shared group id on iOS (so the AutoFill extension can read
///   the same vault).
///
/// Explicitly `@MainActor` because this package target has no default actor
/// isolation (the app targets set `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).
@MainActor
@Observable
public final class AccountController {
    public private(set) var phase: AppPhase = .loading
    public private(set) var account: AccountRecord?

    public let keyStore = KeyStore()
    public private(set) var database: AppDatabase?
    public private(set) var vaultRepository: VaultRepository?
    public private(set) var itemRepository: ItemRepository?
    public private(set) var attachmentStore: AttachmentStore?

    /// Decrypted attachment previews live here while unlocked; wiped on lock.
    public static let previewTempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("2pw-previews", isDirectory: true)

    /// Set when the Secret Key is missing from the Keychain (e.g. fresh machine)
    /// and the lock screen must ask for it.
    public private(set) var needsSecretKeyEntry = false

    /// Human-readable detail shown on the `.databaseError` screen when opening the
    /// on-disk vault failed. Cleared on a successful (re)open.
    public private(set) var bootstrapError: String?

    /// Guards the biometric auto-prompt against re-entrancy.
    private var biometricPromptInFlight = false
    /// The system biometric dialog re-activates the app when it's dismissed
    /// (Cancel / Use Password…), which would re-fire the activation hook and
    /// re-prompt in an endless loop — trapping the user before they can reach the
    /// password field. So auto-prompt at most ONCE per locked session; a fresh
    /// lock re-arms it, and the manual biometric button is unaffected.
    private var biometricAutoPrompted = false

    public let sync: SyncController
    private let autoLock: any AutoLockService
    private let pasteboard: any PasteboardService
    private let appGroupIdentifier: String?

    /// Wired by the app to shed/refresh its decrypted vault view-model. The
    /// overview cache + edit draft live there, not here.
    public var onVaultShouldClearSecrets: (() -> Void)?
    public var onVaultShouldRefresh: (() async -> Void)?

    public init(
        sync: SyncController,
        autoLock: any AutoLockService,
        pasteboard: any PasteboardService,
        appGroupIdentifier: String? = nil
    ) {
        self.sync = sync
        self.autoLock = autoLock
        self.pasteboard = pasteboard
        self.appGroupIdentifier = appGroupIdentifier
    }

    /// One-time setup: open the vault and wire auto-lock. The app shell does the
    /// rest of its platform bootstrap (activation observer, helper controllers).
    public func boot() async {
        await openVaultAndRoute()
        autoLock.onShouldLock = { [weak self] in self?.lock() }
    }

    /// Auto-prompts biometrics when the app activates while locked. Guarded so the
    /// system prompt can't re-enter and so a manual lock (no activation) is silent.
    public func promptBiometricIfAppropriate() {
        guard phase == .locked, biometricUnlockAllowed,
              !biometricPromptInFlight, !biometricAutoPrompted else { return }
        biometricPromptInFlight = true
        biometricAutoPrompted = true
        Task {
            _ = await unlockWithTouchID()
            biometricPromptInFlight = false
        }
    }

    /// Opens the on-disk vault and routes to the right phase. A *recoverable* error
    /// (corruption, a locked file, a failed migration, or a present-but-undecodable
    /// account row) routes to `.databaseError` — NEVER to `.onboarding`. Onboarding's
    /// "create account" path would insert a second account row with a fresh master
    /// key and orphan every already-encrypted item, so a transient open failure must
    /// not be allowed to reach it. `.onboarding` is reached only when the database
    /// opened cleanly and genuinely holds no account.
    public func openVaultAndRoute() async {
        do {
            let db = try AppDatabase.open(appGroupIdentifier: appGroupIdentifier)
            database = db
            vaultRepository = VaultRepository(database: db, keyStore: keyStore)
            itemRepository = ItemRepository(database: db, keyStore: keyStore)
            attachmentStore = try? AttachmentStore(database: db, keyStore: keyStore)
            try? await itemRepository?.purgeTrash()
            if let existing = try await vaultRepository?.account() {
                account = existing
                needsSecretKeyEntry = KeychainStore.loadSecretKey(accountID: existing.id) == nil
                bootstrapError = nil
                biometricAutoPrompted = false
                phase = .locked
                // Sync moves only ciphertext, so it can run while locked.
                await sync.start(database: db)
            } else if try await vaultRepository?.hasItems() == true {
                // Account row missing but items remain — a partially-corrupted
                // vault. Route to the error screen (restore / erase), NEVER to
                // onboarding: a fresh account would mint a new master key and
                // orphan the surviving items (encrypted under the lost key).
                bootstrapError = "Your vault’s items are still here, but its account record is missing. Restore from a backup to recover them, or erase and start over if you have no backup."
                phase = .databaseError
            } else {
                bootstrapError = nil
                phase = .onboarding
            }
        } catch {
            bootstrapError = error.localizedDescription
            phase = .databaseError
        }
    }

    /// Permanently erases the on-disk vault and returns to onboarding. Invoked
    /// ONLY from the gated "erase and start over" control on the database-error
    /// screen, after the user types an explicit confirmation. Irreversible.
    public func eraseVaultAndRestartOnboarding() async {
        phase = .loading
        await sync.stop()
        // Drop every reference to the open database so its file handles close
        // before the files underneath them are deleted.
        database = nil
        vaultRepository = nil
        itemRepository = nil
        attachmentStore = nil
        account = nil
        bootstrapError = nil
        needsSecretKeyEntry = false
        await keyStore.lock()
        try? AppDatabase.destroyOnDiskVault(appGroupIdentifier: appGroupIdentifier)
        // Re-open a fresh, empty database → onboarding.
        await openVaultAndRoute()
    }

    /// Re-attempts opening the vault after a `.databaseError`. The app shell may
    /// follow this with a biometric prompt if it became active.
    public func retryOpeningVault() async {
        phase = .loading
        await openVaultAndRoute()
    }

    // MARK: Onboarding

    public struct OnboardingResult {
        public let secretKey: SecretKey
        public let email: String
    }

    /// Creates the account, default vault, and stores the Secret Key in the
    /// Keychain. Runs key derivation off the main thread.
    public func createAccount(email: String, password: String) async throws -> OnboardingResult {
        guard let vaultRepository else { throw CryptoError.decryptionFailed }
        // Never overwrite an existing vault. Onboarding should only be reachable on a
        // pristine database, but guard here too: if any account row exists, refuse
        // rather than orphan its master key with a second account. The Secret Key is
        // not generated/written until after this check passes.
        guard try await !vaultRepository.hasAccount() else {
            throw VaultRepositoryError.databaseNotEmpty
        }
        let new = try await Task.detached(priority: .userInitiated) {
            try AccountCrypto.createAccount(email: email, password: password)
        }.value
        try KeychainStore.saveSecretKey(new.secretKey, accountID: new.record.accountID)
        try await vaultRepository.createInitialAccount(new.record)
        await keyStore.setMasterKey(new.masterKey)
        try await vaultRepository.createVault(attributes: VaultAttributes(name: "Personal", symbolName: "person.fill", colorToken: "blue"))
        account = try await vaultRepository.account()
        return OnboardingResult(secretKey: new.secretKey, email: email)
    }

    public func finishOnboarding() {
        phase = .unlocked
        autoLock.start()
        Task { await sync.start(database: database) }
    }

    /// New-device flow: adopt a remote account record after verifying the
    /// typed credentials can actually unwrap the master key.
    public func signInToExistingAccount(remote: AccountCrypto.AccountKeyRecord, password: String, typedSecretKey: String) async throws {
        guard let secretKey = SecretKey(parsing: typedSecretKey) else { throw UnlockError.invalidSecretKeyFormat }
        let masterKey: SymmetricKeyBox
        do {
            masterKey = try await Task.detached(priority: .userInitiated) {
                SymmetricKeyBox(key: try AccountCrypto.unlock(record: remote, password: password, secretKey: secretKey))
            }.value
        } catch {
            throw UnlockError.wrongCredentials
        }
        try KeychainStore.saveSecretKey(secretKey, accountID: remote.accountID)
        try await vaultRepository?.saveAccount(remote)
        account = try await vaultRepository?.account()
        await keyStore.setMasterKey(masterKey.key)
        UserDefaults.standard.set(Date(), forKey: SettingsKeys.lastPasswordUnlock)
        phase = .unlocked
        autoLock.start()
        await sync.start(database: database)
    }

    // MARK: Lock / unlock

    public enum UnlockError: Error {
        case wrongCredentials
        case missingSecretKey
        /// The typed Secret Key isn't a valid key (wrong format/length/prefix) —
        /// distinct from "the credentials didn't unlock", so the UI can guide the
        /// user to re-check the key itself.
        case invalidSecretKeyFormat
    }

    public func unlock(password: String, typedSecretKey: String? = nil) async throws {
        guard let account else { throw UnlockError.wrongCredentials }
        let secretKey: SecretKey
        if let typed = typedSecretKey, !typed.isEmpty {
            guard let parsed = SecretKey(parsing: typed) else { throw UnlockError.invalidSecretKeyFormat }
            secretKey = parsed
        } else if let stored = KeychainStore.loadSecretKey(accountID: account.id) {
            secretKey = stored
        } else {
            needsSecretKeyEntry = true
            throw UnlockError.missingSecretKey
        }

        let record = account.keyRecord
        let masterKey: SymmetricKeyBox
        do {
            masterKey = try await Task.detached(priority: .userInitiated) {
                SymmetricKeyBox(key: try AccountCrypto.unlock(record: record, password: password, secretKey: secretKey))
            }.value
        } catch {
            throw UnlockError.wrongCredentials
        }

        // Successful manual unlock with a typed key: persist it again.
        if typedSecretKey != nil {
            try? KeychainStore.saveSecretKey(secretKey, accountID: account.id)
            needsSecretKeyEntry = false
        }
        await keyStore.setMasterKey(masterKey.key)
        UserDefaults.standard.set(Date(), forKey: SettingsKeys.lastPasswordUnlock)
        phase = .unlocked
        autoLock.start()
    }

    public enum PasswordChangeError: Error {
        case wrongCurrentPassword
        case notUnlocked
    }

    /// Changes the account password: verifies the current one by a full key
    /// derivation, then re-wraps the (unchanged) master key under the new AUK.
    /// Biometric unlock stays valid because the master key itself doesn't change.
    public func changeAccountPassword(current: String, new: String) async throws {
        guard let account, let vaultRepository else { throw PasswordChangeError.notUnlocked }
        guard let masterKey = await keyStore.masterKey else { throw PasswordChangeError.notUnlocked }
        guard let secretKey = KeychainStore.loadSecretKey(accountID: account.id) else {
            throw UnlockError.missingSecretKey
        }
        let record = account.keyRecord
        let masterKeyBox = SymmetricKeyBox(key: masterKey)

        let newRecord = try await Task.detached(priority: .userInitiated) {
            guard (try? AccountCrypto.unlock(record: record, password: current, secretKey: secretKey)) != nil else {
                throw PasswordChangeError.wrongCurrentPassword
            }
            return try AccountCrypto.changePassword(
                record: record,
                masterKey: masterKeyBox.key,
                newPassword: new,
                secretKey: secretKey
            )
        }.value

        try await vaultRepository.saveAccount(newRecord)
        self.account = try await vaultRepository.account()
        UserDefaults.standard.set(Date(), forKey: SettingsKeys.lastPasswordUnlock)
        // Push the re-wrapped account record to iCloud (if sync is active).
        sync.kick()
    }

    /// Verifies the account password by a full key derivation. No state change —
    /// used to gate revealing the Secret Key / re-saving the Emergency Kit.
    public func verifyAccountPassword(_ password: String) async -> Bool {
        guard let account, let secretKey = KeychainStore.loadSecretKey(accountID: account.id) else { return false }
        let record = account.keyRecord
        return await Task.detached(priority: .userInitiated) {
            (try? AccountCrypto.unlock(record: record, password: password, secretKey: secretKey)) != nil
        }.value
    }

    // MARK: Recovery code

    public enum RecoveryError: Error {
        case notUnlocked
        case wrongCurrentPassword
        case invalidCode
        case noRecoveryConfigured
        case noAccountFound
    }

    /// True when an opt-in recovery code is currently active for this account.
    public var hasRecoveryCode: Bool { account?.recoveryEnabled == true }

    /// Generates (or rotates) the recovery code. Gated on re-entering the current
    /// password — you can only create a recovery path while you still have access.
    /// Escrows the master key + Secret Key sealed under the new code (synced via
    /// iCloud), and returns the code to display once.
    public func createRecoveryCode(currentPassword: String) async throws -> RecoveryCode {
        guard let account, let vaultRepository else { throw RecoveryError.notUnlocked }
        guard let masterKey = await keyStore.masterKey else { throw RecoveryError.notUnlocked }
        guard let secretKey = KeychainStore.loadSecretKey(accountID: account.id) else {
            throw UnlockError.missingSecretKey
        }
        guard await verifyAccountPassword(currentPassword) else { throw RecoveryError.wrongCurrentPassword }
        let accountID = account.id
        let masterKeyBox = SymmetricKeyBox(key: masterKey)
        let result = try await Task.detached(priority: .userInitiated) {
            try AccountCrypto.enableRecovery(masterKey: masterKeyBox.key, secretKey: secretKey, accountID: accountID)
        }.value
        try await vaultRepository.setRecoveryFields(
            recoveryBlob: result.recoveryBlob, encRecoveryCode: result.encRecoveryCode, accountID: accountID
        )
        self.account = try await vaultRepository.account()
        sync.kick()
        return result.code
    }

    /// Decrypts the stored recovery code for re-viewing while unlocked.
    public func revealRecoveryCode() async -> String? {
        guard let account, account.recoveryEnabled, let enc = account.encRecoveryCode else { return nil }
        guard let masterKey = await keyStore.masterKey else { return nil }
        let accountID = account.id
        let box = SymmetricKeyBox(key: masterKey)
        return await Task.detached(priority: .userInitiated) {
            try? AccountCrypto.revealRecoveryCode(encRecoveryCode: enc, masterKey: box.key, accountID: accountID)
        }.value
    }

    /// Turns off recovery, destroying the escrowed material (locally and, via the
    /// overwrite-with-random scheme, in iCloud) so the old code no longer works.
    /// The local blob is overwritten immediately, so the code is dead on-device at
    /// once. When sync is running we then AWAIT the push so the un-openable account
    /// record reaches iCloud before returning; if sync is off/offline the stale
    /// cloud copy is overwritten on the next sync instead (the account record is
    /// always re-enqueued).
    public func disableRecovery() async throws {
        guard let account, let vaultRepository else { throw RecoveryError.notUnlocked }
        let tombstone = try AccountCrypto.recoveryTombstone()
        try await vaultRepository.disableRecovery(tombstone: tombstone, accountID: account.id)
        self.account = try await vaultRepository.account()
        await sync.pushChangesAndWait()
    }

    /// Regains access with a recovery code when the password is forgotten, then
    /// sets a new password. Works on this device or, on a fresh machine, by
    /// pulling the account record from iCloud. The recovery code stays valid.
    public func recoverWithCode(_ codeString: String, newPassword: String) async throws {
        guard let code = RecoveryCode(parsing: codeString) else { throw RecoveryError.invalidCode }
        guard let vaultRepository else { throw RecoveryError.notUnlocked }

        let record: AccountCrypto.AccountKeyRecord
        if let local = account {
            record = local.keyRecord
        } else if let remote = try await SyncController.fetchRemoteAccount() {
            record = remote
        } else {
            throw RecoveryError.noAccountFound
        }
        guard record.recoveryEnabled, let recoveryBlob = record.recoveryBlob else {
            throw RecoveryError.noRecoveryConfigured
        }
        let accountID = record.accountID

        let recovered: (masterKey: SymmetricKeyBox, secretKey: SecretKey)
        do {
            recovered = try await Task.detached(priority: .userInitiated) {
                let r = try AccountCrypto.recover(recoveryBlob: recoveryBlob, code: code, accountID: accountID)
                return (SymmetricKeyBox(key: r.masterKey), r.secretKey)
            }.value
        } catch {
            throw RecoveryError.invalidCode
        }

        // Persist the recovered Secret Key and set the new password (re-wraps the
        // master key under the new AUK; recovery material carries through).
        try KeychainStore.saveSecretKey(recovered.secretKey, accountID: accountID)
        let masterBox = recovered.masterKey
        let secretKey = recovered.secretKey
        let newRecord = try await Task.detached(priority: .userInitiated) {
            try AccountCrypto.changePassword(
                record: record, masterKey: masterBox.key, newPassword: newPassword, secretKey: secretKey
            )
        }.value

        try await vaultRepository.saveAccount(newRecord)
        self.account = try await vaultRepository.account()
        await keyStore.setMasterKey(masterBox.key)
        needsSecretKeyEntry = false
        UserDefaults.standard.set(Date(), forKey: SettingsKeys.lastPasswordUnlock)
        phase = .unlocked
        autoLock.start()
        await sync.start(database: database)
        sync.kick()
    }

    // MARK: Encrypted backup

    public enum BackupRestoreError: Error {
        case notUnlocked
        case wrongCredentials
    }

    /// Produces an encrypted `.pwbackup` of the whole vault, sealed under the
    /// current master key. Requires being unlocked.
    /// `includeRecovery: false` produces a password-only backup (the recovery
    /// escrow is stripped from the header), so the exported file can't be opened
    /// with a recovery code — the way to make a backup that disabling/rotating a
    /// code actually covers.
    public func makeBackupData(includeRecovery: Bool = true) async throws -> Data {
        guard let database, let attachmentStore else { throw BackupRestoreError.notUnlocked }
        guard let masterKey = await keyStore.masterKey else { throw BackupRestoreError.notUnlocked }
        let store = BackupStore(database: database, attachmentsDirectory: attachmentStore.directory)
        let collected = try await store.collect()
        let box = SymmetricKeyBox(key: masterKey)
        return try await Task.detached(priority: .userInitiated) {
            try BackupArchive.encode(
                account: collected.account, contents: collected.contents,
                masterKey: box.key, createdAt: Date(), includeRecovery: includeRecovery
            )
        }.value
    }

    /// Restores a backup using the account password + Secret Key. Replaces the
    /// local vault entirely. Works on a fresh Mac (onboarding) or the current one.
    public func restoreBackup(fileData: Data, password: String, typedSecretKey: String) async throws {
        guard let secretKey = SecretKey(parsing: typedSecretKey) else { throw BackupRestoreError.wrongCredentials }
        let file = try BackupArchive.decode(fileData) // throws on corrupt/unsupported
        let header = file.account.keyRecord
        let masterBox: SymmetricKeyBox
        do {
            masterBox = try await Task.detached(priority: .userInitiated) {
                SymmetricKeyBox(key: try AccountCrypto.unlock(record: header, password: password, secretKey: secretKey))
            }.value
        } catch {
            throw BackupRestoreError.wrongCredentials
        }
        let contents = try BackupArchive.openContents(file, masterKey: masterBox.key)
        try await applyRestore(accountToStore: file.account, contents: contents, masterKey: masterBox.key, secretKey: secretKey)
    }

    /// Restores a backup using a recovery code, then sets a new password (the
    /// backup's old password is unknown). Replaces the local vault entirely.
    public func restoreBackup(fileData: Data, recoveryCode: String, newPassword: String) async throws {
        guard let code = RecoveryCode(parsing: recoveryCode) else { throw BackupRestoreError.wrongCredentials }
        let file = try BackupArchive.decode(fileData)
        let header = file.account.keyRecord
        guard header.recoveryEnabled, let recoveryBlob = header.recoveryBlob else {
            throw BackupRestoreError.wrongCredentials
        }
        let recovered: (master: SymmetricKeyBox, secret: SecretKey)
        do {
            recovered = try await Task.detached(priority: .userInitiated) {
                let r = try AccountCrypto.recover(recoveryBlob: recoveryBlob, code: code, accountID: header.accountID)
                return (SymmetricKeyBox(key: r.masterKey), r.secretKey)
            }.value
        } catch {
            throw BackupRestoreError.wrongCredentials
        }
        let contents = try BackupArchive.openContents(file, masterKey: recovered.master.key)
        // Re-wrap the master key under the new password so normal unlock works after.
        let newKeyRecord = try await Task.detached(priority: .userInitiated) {
            try AccountCrypto.changePassword(
                record: header, masterKey: recovered.master.key,
                newPassword: newPassword, secretKey: recovered.secret
            )
        }.value
        var accountToStore = file.account
        accountToStore.kdfSalt = newKeyRecord.kdfSalt
        accountToStore.encMasterKey = newKeyRecord.encMasterKey
        accountToStore.recoveryEnabled = newKeyRecord.recoveryEnabled
        accountToStore.recoveryBlob = newKeyRecord.recoveryBlob
        accountToStore.encRecoveryCode = newKeyRecord.encRecoveryCode
        try await applyRestore(accountToStore: accountToStore, contents: contents, masterKey: recovered.master.key, secretKey: recovered.secret)
    }

    private func applyRestore(accountToStore: AccountRecord, contents: BackupContents, masterKey: SymmetricKey, secretKey: SecretKey) async throws {
        guard let database, let attachmentStore, let vaultRepository else { throw BackupRestoreError.notUnlocked }
        // Tear down any running sync engine first, and AWAIT it so the old engine
        // is fully released before we wipe its state token. `restore` clears the
        // persisted CKSyncEngine token, but a live engine keeps its token in memory
        // and `start()` is a no-op while it's running — so without this stop the
        // trailing `start()` wouldn't re-bootstrap and the device would resume from
        // the pre-restore token. Awaiting guarantees no lingering engine can
        // re-persist the stale token across the destructive restore; the trailing
        // `start()` then recreates the engine for a full fetch+reconcile.
        await sync.stop()
        let store = BackupStore(database: database, attachmentsDirectory: attachmentStore.directory)
        try await store.restore(account: accountToStore, contents: contents)
        try KeychainStore.saveSecretKey(secretKey, accountID: accountToStore.id)
        // Biometrics' per-device Secure-Enclave wrap may no longer match the
        // restored master key, so reset it; the user can re-enroll while unlocked.
        BiometricUnlock.disable()
        await keyStore.lock()
        await keyStore.setMasterKey(masterKey)
        account = try await vaultRepository.account()
        needsSecretKeyEntry = false
        onVaultShouldClearSecrets?()
        await onVaultShouldRefresh?()
        UserDefaults.standard.set(Date(), forKey: SettingsKeys.lastPasswordUnlock)
        phase = .unlocked
        autoLock.start()
        await sync.start(database: database)
        sync.kick()
    }

    public func unlockWithTouchID() async -> Bool {
        guard biometricUnlockAllowed else { return false }
        // Showing the system dialog (whether from the manual biometric button or
        // the auto-prompt) re-activates the app when it's dismissed, which fires
        // the activation hook. Mark the session as prompted up front so that
        // dismissal can't trigger a second auto-prompt (the "Cancel twice" bug).
        biometricAutoPrompted = true
        let result = await BiometricUnlock.unlock()
        switch result {
        case .success(let masterKey):
            await keyStore.setMasterKey(masterKey)
            phase = .unlocked
            autoLock.start()
            return true
        case .invalidated:
            BiometricUnlock.disable()
            return false
        case .userCancelled, .unavailable:
            return false
        }
    }

    /// Biometric unlock is disabled once "require password after N hours" elapses.
    public var biometricUnlockAllowed: Bool {
        guard BiometricUnlock.isAvailable && BiometricUnlock.isEnrolled else { return false }
        let hours = UserDefaults.standard.object(forKey: SettingsKeys.requirePasswordAfterHours) as? Int ?? 72
        guard hours > 0 else { return true }
        let last = UserDefaults.standard.object(forKey: SettingsKeys.lastPasswordUnlock) as? Date ?? .distantPast
        return Date().timeIntervalSince(last) < Double(hours) * 3600
    }

    public func lock() {
        guard phase == .unlocked else { return }
        autoLock.stop()
        Task { await keyStore.lock() }
        try? FileManager.default.removeItem(at: Self.previewTempDirectory)
        // Shed every decrypted secret the app holds outside the key store:
        // the in-memory overview cache + any in-progress edit draft, and a
        // password/Secret Key still sitting in the clipboard.
        onVaultShouldClearSecrets?()
        pasteboard.clearSecret()
        biometricAutoPrompted = false
        phase = .locked
    }
}
