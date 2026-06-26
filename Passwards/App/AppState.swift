import SwiftUI
import AppKit
import PasswardsCore
import PasswardsOrchestration

/// macOS app shell around the shared `AccountController` (PasswardsOrchestration).
/// Owns the macOS-only helpers — auto-lock monitor, browser bridge, SSH agent,
/// CLI control, and the `didBecomeActive` biometric observer — and forwards the
/// account/vault lifecycle to `core` so the views keep calling `appState.unlock(…)`
/// etc. unchanged. The iOS app reuses `AccountController` directly with its own shell.
@Observable
final class AppState {
    let core: AccountController

    // Re-expose the lifecycle's nested types so existing call sites keep working
    // (e.g. `AppState.UnlockError`, `AppState.OnboardingResult`).
    typealias OnboardingResult = AccountController.OnboardingResult
    typealias UnlockError = AccountController.UnlockError
    typealias PasswordChangeError = AccountController.PasswordChangeError
    typealias RecoveryError = AccountController.RecoveryError
    typealias BackupRestoreError = AccountController.BackupRestoreError

    let autoLock: AutoLockMonitor
    private(set) var browserBridge: BrowserBridgeController?
    private(set) var sshAgent: SSHAgentController?
    private(set) var cliControl: CLIControlController?

    /// Shared by the main window and Quick Access. Created at bootstrap;
    /// holds no decrypted data until `load()` runs after unlock.
    private(set) var vaultStore: VaultStore?

    /// Decrypted attachment previews live here while unlocked; wiped on lock.
    static let previewTempDirectory = AccountController.previewTempDirectory

    init() {
        let monitor = AutoLockMonitor()
        self.autoLock = monitor
        self.core = AccountController(
            sync: SyncController(),
            autoLock: monitor,
            pasteboard: MacPasteboardService()
        )
        // The decrypted overview cache + edit draft live in VaultStore, so the
        // controller calls back here to shed/refresh them on lock/restore.
        core.onVaultShouldClearSecrets = { [weak self] in self?.vaultStore?.clearSecrets() }
        core.onVaultShouldRefresh = { [weak self] in await self?.vaultStore?.refresh() }
    }

    // MARK: Forwarded state (read by views via Observation through `core`)

    var phase: AppPhase { core.phase }
    var account: AccountRecord? { core.account }
    var keyStore: KeyStore { core.keyStore }
    var database: AppDatabase? { core.database }
    var vaultRepository: VaultRepository? { core.vaultRepository }
    var itemRepository: ItemRepository? { core.itemRepository }
    var attachmentStore: AttachmentStore? { core.attachmentStore }
    var needsSecretKeyEntry: Bool { core.needsSecretKeyEntry }
    var bootstrapError: String? { core.bootstrapError }
    var hasRecoveryCode: Bool { core.hasRecoveryCode }
    var biometricUnlockAllowed: Bool { core.biometricUnlockAllowed }
    var sync: SyncController { core.sync }

    func ensureVaultStore() -> VaultStore {
        if let vaultStore { return vaultStore }
        let store = VaultStore(appState: self)
        vaultStore = store
        return store
    }

    func bootstrap() async {
        await core.boot()
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
            Task { @MainActor [weak self] in self?.core.promptBiometricIfAppropriate() }
        }
        // Cover the launch case directly, in case the first activation fired
        // before this observer was registered.
        if core.phase == .locked, NSApp.isActive {
            core.promptBiometricIfAppropriate()
        }
    }

    func promptBiometricIfAppropriate() { core.promptBiometricIfAppropriate() }

    // MARK: Forwarded lifecycle

    func openVaultAndRoute() async { await core.openVaultAndRoute() }
    func eraseVaultAndRestartOnboarding() async { await core.eraseVaultAndRestartOnboarding() }

    func retryOpeningVault() async {
        await core.retryOpeningVault()
        if core.phase == .locked, NSApp.isActive { core.promptBiometricIfAppropriate() }
    }

    func createAccount(email: String, password: String) async throws -> OnboardingResult {
        try await core.createAccount(email: email, password: password)
    }
    func finishOnboarding() { core.finishOnboarding() }
    func signInToExistingAccount(remote: AccountCrypto.AccountKeyRecord, password: String, typedSecretKey: String) async throws {
        try await core.signInToExistingAccount(remote: remote, password: password, typedSecretKey: typedSecretKey)
    }
    func unlock(password: String, typedSecretKey: String? = nil) async throws {
        try await core.unlock(password: password, typedSecretKey: typedSecretKey)
    }
    func changeAccountPassword(current: String, new: String) async throws {
        try await core.changeAccountPassword(current: current, new: new)
    }
    func verifyAccountPassword(_ password: String) async -> Bool {
        await core.verifyAccountPassword(password)
    }
    func createRecoveryCode(currentPassword: String) async throws -> RecoveryCode {
        try await core.createRecoveryCode(currentPassword: currentPassword)
    }
    func revealRecoveryCode() async -> String? { await core.revealRecoveryCode() }
    func disableRecovery() async throws { try await core.disableRecovery() }
    func recoverWithCode(_ code: String, newPassword: String) async throws {
        try await core.recoverWithCode(code, newPassword: newPassword)
    }
    func makeBackupData(includeRecovery: Bool = true) async throws -> Data {
        try await core.makeBackupData(includeRecovery: includeRecovery)
    }
    func restoreBackup(fileData: Data, password: String, typedSecretKey: String) async throws {
        try await core.restoreBackup(fileData: fileData, password: password, typedSecretKey: typedSecretKey)
    }
    func restoreBackup(fileData: Data, recoveryCode: String, newPassword: String) async throws {
        try await core.restoreBackup(fileData: fileData, recoveryCode: recoveryCode, newPassword: newPassword)
    }
    func unlockWithTouchID() async -> Bool { await core.unlockWithTouchID() }
    func lock() { core.lock() }
}

/// macOS pasteboard adapter for the shared `PasteboardService` seam.
struct MacPasteboardService: PasteboardService {
    func copy(_ value: String, concealed: Bool) { ClipboardManager.copy(value, concealed: concealed) }
    func clearSecret() { ClipboardManager.clearOnLock() }
}
