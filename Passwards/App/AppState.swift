import SwiftUI
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
