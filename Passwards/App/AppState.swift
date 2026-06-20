import SwiftUI
import AppKit
import PasswardsCore

enum AppPhase: Equatable {
    case loading
    case onboarding
    case locked
    case unlocked
}

/// Root state machine: onboarding → locked ⇄ unlocked. Owns the database,
/// key store, and repositories; the lock screen and main window both hang off it.
@Observable
final class AppState {
    private(set) var phase: AppPhase = .loading
    private(set) var account: AccountRecord?

    let keyStore = KeyStore()
    private(set) var database: AppDatabase?
    private(set) var vaultRepository: VaultRepository?
    private(set) var itemRepository: ItemRepository?
    private(set) var attachmentStore: AttachmentStore?

    /// Decrypted attachment previews live here while unlocked; wiped on lock.
    static let previewTempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("2pw-previews", isDirectory: true)

    /// Set when the Secret Key is missing from the Keychain (e.g. fresh machine)
    /// and the lock screen must ask for it.
    private(set) var needsSecretKeyEntry = false

    /// Guards the Touch ID auto-prompt against re-entrancy.
    private var biometricPromptInFlight = false

    let autoLock = AutoLockMonitor()
    let sync = SyncController()
    private(set) var browserBridge: BrowserBridgeController?
    private(set) var sshAgent: SSHAgentController?
    private(set) var cliControl: CLIControlController?

    /// Shared by the main window and Quick Access. Created at bootstrap;
    /// holds no decrypted data until `load()` runs after unlock.
    private(set) var vaultStore: VaultStore?

    func ensureVaultStore() -> VaultStore {
        if let vaultStore { return vaultStore }
        let store = VaultStore(appState: self)
        vaultStore = store
        return store
    }

    func bootstrap() async {
        do {
            let db = try AppDatabase.open()
            database = db
            vaultRepository = VaultRepository(database: db, keyStore: keyStore)
            itemRepository = ItemRepository(database: db, keyStore: keyStore)
            attachmentStore = try? AttachmentStore(database: db, keyStore: keyStore)
            try? await itemRepository?.purgeTrash()
            if let existing = try await vaultRepository?.account() {
                account = existing
                needsSecretKeyEntry = KeychainStore.loadSecretKey(accountID: existing.id) == nil
                phase = .locked
                // Sync moves only ciphertext, so it can run while locked.
                await sync.start(database: db)
            } else {
                phase = .onboarding
            }
        } catch {
            assertionFailure("database bootstrap failed: \(error)")
            phase = .onboarding
        }
        autoLock.onShouldLock = { [weak self] in self?.lock() }
        // The bridge serves only lock-state info until unlocked.
        let bridge = BrowserBridgeController(appState: self)
        bridge.start()
        browserBridge = bridge

        // SSH agent: serves vault SSH Key items over a Unix socket when enabled.
        // It exposes nothing while locked (keys are decrypted on demand).
        let agent = SSHAgentController(appState: self)
        agent.startIfEnabled()
        sshAgent = agent

        // CLI control channel: serves `passwards item get/list` to the local
        // CLI when enabled; secret reads are gated on Touch ID, locked otherwise.
        let cli = CLIControlController(appState: self)
        cli.startIfEnabled()
        cliControl = cli

        // Offer Touch ID when the app is launched or brought back to the
        // foreground while locked — NOT the instant you manually lock (locking
        // keeps the app active, so no activation fires). Mirrors 1Password 8.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.promptBiometricIfAppropriate() }
        }
        // Cover the launch case directly, in case the first activation fired
        // before this observer was registered.
        if phase == .locked, NSApp.isActive {
            promptBiometricIfAppropriate()
        }
    }

    /// Auto-prompts Touch ID when the app activates while locked. Guarded so the
    /// system prompt can't re-enter and so a manual lock (no activation) is silent.
    func promptBiometricIfAppropriate() {
        guard phase == .locked, biometricUnlockAllowed, !biometricPromptInFlight else { return }
        biometricPromptInFlight = true
        Task {
            _ = await unlockWithTouchID()
            biometricPromptInFlight = false
        }
    }

    // MARK: Onboarding

    struct OnboardingResult {
        let secretKey: SecretKey
        let email: String
    }

    /// Creates the account, default vault, and stores the Secret Key in the
    /// Keychain. Runs key derivation off the main thread.
    func createAccount(email: String, password: String) async throws -> OnboardingResult {
        let new = try await Task.detached(priority: .userInitiated) {
            try AccountCrypto.createAccount(email: email, password: password)
        }.value
        try KeychainStore.saveSecretKey(new.secretKey, accountID: new.record.accountID)
        guard let vaultRepository else { throw CryptoError.decryptionFailed }
        try await vaultRepository.saveAccount(new.record)
        await keyStore.setMasterKey(new.masterKey)
        try await vaultRepository.createVault(attributes: VaultAttributes(name: "Personal", symbolName: "person.fill", colorToken: "blue"))
        account = try await vaultRepository.account()
        return OnboardingResult(secretKey: new.secretKey, email: email)
    }

    func finishOnboarding() {
        phase = .unlocked
        autoLock.start()
        Task { await sync.start(database: database) }
    }

    /// New-device flow: adopt a remote account record after verifying the
    /// typed credentials can actually unwrap the master key.
    func signInToExistingAccount(remote: AccountCrypto.AccountKeyRecord, password: String, typedSecretKey: String) async throws {
        guard let secretKey = SecretKey(parsing: typedSecretKey) else { throw UnlockError.wrongCredentials }
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

    enum UnlockError: Error {
        case wrongCredentials
        case missingSecretKey
    }

    func unlock(password: String, typedSecretKey: String? = nil) async throws {
        guard let account else { throw UnlockError.wrongCredentials }
        let secretKey: SecretKey
        if let typed = typedSecretKey, !typed.isEmpty {
            guard let parsed = SecretKey(parsing: typed) else { throw UnlockError.wrongCredentials }
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

    enum PasswordChangeError: Error {
        case wrongCurrentPassword
        case notUnlocked
    }

    /// Changes the account password: verifies the current one by a full key
    /// derivation, then re-wraps the (unchanged) master key under the new AUK.
    /// Touch ID stays valid because the master key itself doesn't change.
    func changeAccountPassword(current: String, new: String) async throws {
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
    func verifyAccountPassword(_ password: String) async -> Bool {
        guard let account, let secretKey = KeychainStore.loadSecretKey(accountID: account.id) else { return false }
        let record = account.keyRecord
        return await Task.detached(priority: .userInitiated) {
            (try? AccountCrypto.unlock(record: record, password: password, secretKey: secretKey)) != nil
        }.value
    }

    // MARK: Recovery code

    enum RecoveryError: Error {
        case notUnlocked
        case wrongCurrentPassword
        case invalidCode
        case noRecoveryConfigured
        case noAccountFound
    }

    /// True when an opt-in recovery code is currently active for this account.
    var hasRecoveryCode: Bool { account?.recoveryEnabled == true }

    /// Generates (or rotates) the recovery code. Gated on re-entering the current
    /// password — you can only create a recovery path while you still have access.
    /// Escrows the master key + Secret Key sealed under the new code (synced via
    /// iCloud), and returns the code to display once.
    func createRecoveryCode(currentPassword: String) async throws -> RecoveryCode {
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
    func revealRecoveryCode() async -> String? {
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
    func disableRecovery() async throws {
        guard let account, let vaultRepository else { throw RecoveryError.notUnlocked }
        let tombstone = try AccountCrypto.recoveryTombstone()
        try await vaultRepository.disableRecovery(tombstone: tombstone, accountID: account.id)
        self.account = try await vaultRepository.account()
        sync.kick()
    }

    /// Regains access with a recovery code when the password is forgotten, then
    /// sets a new password. Works on this device or, on a fresh machine, by
    /// pulling the account record from iCloud. The recovery code stays valid.
    func recoverWithCode(_ codeString: String, newPassword: String) async throws {
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

    enum BackupRestoreError: Error {
        case notUnlocked
        case wrongCredentials
    }

    /// Produces an encrypted `.pwbackup` of the whole vault, sealed under the
    /// current master key. Requires being unlocked.
    func makeBackupData() async throws -> Data {
        guard let database, let attachmentStore else { throw BackupRestoreError.notUnlocked }
        guard let masterKey = await keyStore.masterKey else { throw BackupRestoreError.notUnlocked }
        let store = BackupStore(database: database, attachmentsDirectory: attachmentStore.directory)
        let collected = try await store.collect()
        let box = SymmetricKeyBox(key: masterKey)
        return try await Task.detached(priority: .userInitiated) {
            try BackupArchive.encode(
                account: collected.account, contents: collected.contents,
                masterKey: box.key, createdAt: Date()
            )
        }.value
    }

    /// Restores a backup using the account password + Secret Key. Replaces the
    /// local vault entirely. Works on a fresh Mac (onboarding) or the current one.
    func restoreBackup(fileData: Data, password: String, typedSecretKey: String) async throws {
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
    func restoreBackup(fileData: Data, recoveryCode: String, newPassword: String) async throws {
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
        let store = BackupStore(database: database, attachmentsDirectory: attachmentStore.directory)
        try await store.restore(account: accountToStore, contents: contents)
        try KeychainStore.saveSecretKey(secretKey, accountID: accountToStore.id)
        // Touch ID's per-device Secure-Enclave wrap may no longer match the
        // restored master key, so reset it; the user can re-enroll while unlocked.
        BiometricUnlock.disable()
        await keyStore.lock()
        await keyStore.setMasterKey(masterKey)
        account = try await vaultRepository.account()
        needsSecretKeyEntry = false
        vaultStore?.clearSecrets()
        await vaultStore?.refresh()
        UserDefaults.standard.set(Date(), forKey: SettingsKeys.lastPasswordUnlock)
        phase = .unlocked
        autoLock.start()
        await sync.start(database: database)
        sync.kick()
    }

    func unlockWithTouchID() async -> Bool {
        guard biometricUnlockAllowed else { return false }
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

    /// Touch ID is disabled once "require password after N hours" has elapsed.
    var biometricUnlockAllowed: Bool {
        guard BiometricUnlock.isAvailable && BiometricUnlock.isEnrolled else { return false }
        let hours = UserDefaults.standard.object(forKey: SettingsKeys.requirePasswordAfterHours) as? Int ?? 72
        guard hours > 0 else { return true }
        let last = UserDefaults.standard.object(forKey: SettingsKeys.lastPasswordUnlock) as? Date ?? .distantPast
        return Date().timeIntervalSince(last) < Double(hours) * 3600
    }

    func lock() {
        guard phase == .unlocked else { return }
        autoLock.stop()
        Task { await keyStore.lock() }
        try? FileManager.default.removeItem(at: Self.previewTempDirectory)
        // Shed every decrypted secret the app holds outside the key store:
        // the in-memory overview cache + any in-progress edit draft, and a
        // password/Secret Key still sitting in the clipboard.
        vaultStore?.clearSecrets()
        ClipboardManager.clearOnLock()
        phase = .locked
    }
}

/// Sendable wrapper to move a SymmetricKey out of a detached task.
struct SymmetricKeyBox: @unchecked Sendable {
    let key: CryptoKit.SymmetricKey
}

import CryptoKit

nonisolated enum SettingsKeys {
    static let lastPasswordUnlock = "lastPasswordUnlock"
    static let requirePasswordAfterHours = "requirePasswordAfterHours"
    static let lockOnSleep = "lockOnSleep"
    static let lockOnScreensaver = "lockOnScreensaver"
    static let idleLockMinutes = "idleLockMinutes"
    static let lockWhenBackgroundMinutes = "lockWhenBackgroundMinutes"
    static let clipboardClearSeconds = "clipboardClearSeconds"
    static let concealPasswords = "concealPasswords"
    static let richIconsEnabled = "richIconsEnabled"
    static let watchtowerHIBPEnabled = "watchtowerHIBPEnabled"
    static let watchtowerEnabled = "watchtowerEnabled"
    static let theme = "appTheme"
    static let sshAgentEnabled = "sshAgentEnabled"
    static let sshApprovalRequired = "sshApprovalRequired"
    static let sshApprovalCacheSeconds = "sshApprovalCacheSeconds"
    static let cliAccessEnabled = "cliAccessEnabled"
}
