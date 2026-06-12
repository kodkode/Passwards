import SwiftUI
import ServiceManagement
import KeyboardShortcuts
import TwoPasswordCore

struct SettingsScene: View {
    let appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            SecuritySettingsView(appState: appState)
                .tabItem { Label("Security", systemImage: "lock") }
            PrivacySettingsView()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            BrowserSettingsView()
                .tabItem { Label("Browser", systemImage: "globe") }
            AdvancedSettingsView(appState: appState)
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 480)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Keyboard Shortcuts") {
                KeyboardShortcuts.Recorder("Show Quick Access:", name: .toggleQuickAccess)
                KeyboardShortcuts.Recorder("Lock 2Password:", name: .lockApp)
            }
            Section {
                Toggle("Start 2Password at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) {
                        do {
                            if launchAtLogin {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Toggle("Show 2Password in the menu bar", isOn: $showMenuBarExtra)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

struct AppearanceSettingsView: View {
    @AppStorage(SettingsKeys.theme) private var theme = "system"

    var body: some View {
        Form {
            Picker("Theme", selection: $theme) {
                Text("Match System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.inline)
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

struct SecuritySettingsView: View {
    let appState: AppState
    @AppStorage(SettingsKeys.idleLockMinutes) private var idleLockMinutes = 10
    @AppStorage(SettingsKeys.lockWhenBackgroundMinutes) private var lockWhenBackgroundMinutes = 0
    @AppStorage(SettingsKeys.lockOnSleep) private var lockOnSleep = true
    @AppStorage(SettingsKeys.lockOnScreensaver) private var lockOnScreensaver = true
    @AppStorage(SettingsKeys.requirePasswordAfterHours) private var requirePasswordAfterHours = 72
    @AppStorage(SettingsKeys.clipboardClearSeconds) private var clipboardClearSeconds = 90
    @State private var touchIDEnabled = BiometricUnlock.isEnrolled
    @State private var changePasswordShown = false
    @State private var emergencyKitShown = false

    var body: some View {
        Form {
            Section("Account Password") {
                Button("Change Account Password…") {
                    changePasswordShown = true
                }
                .disabled(appState.phase != .unlocked)
                if appState.phase != .unlocked {
                    Text("Unlock 2Password to change the account password.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Emergency Kit") {
                Button("View Secret Key & Save Emergency Kit…") {
                    emergencyKitShown = true
                }
                .disabled(appState.phase != .unlocked)
                Text("The Emergency Kit contains your Secret Key — you'll need it to set up 2Password on a new device. Keep a copy somewhere safe.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Unlock") {
                if BiometricUnlock.isAvailable {
                    Toggle("Unlock with Touch ID", isOn: $touchIDEnabled)
                        .onChange(of: touchIDEnabled) {
                            if touchIDEnabled {
                                Task {
                                    if let masterKey = await appState.keyStore.masterKey {
                                        try? BiometricUnlock.enroll(masterKey: masterKey)
                                    } else {
                                        touchIDEnabled = false
                                    }
                                }
                            } else {
                                BiometricUnlock.disable()
                            }
                        }
                        .disabled(appState.phase != .unlocked && !touchIDEnabled)
                } else {
                    Text("Touch ID is not available on this Mac.")
                        .foregroundStyle(.secondary)
                }
                Picker("Require account password after", selection: $requirePasswordAfterHours) {
                    Text("8 hours").tag(8)
                    Text("1 day").tag(24)
                    Text("3 days").tag(72)
                    Text("14 days").tag(336)
                    Text("Never").tag(0)
                }
            }
            Section("Auto-Lock") {
                Picker("Lock after system is idle for", selection: $idleLockMinutes) {
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("Never").tag(0)
                }
                Picker("Lock when in the background for", selection: $lockWhenBackgroundMinutes) {
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                    Text("1 hour").tag(60)
                    Text("Never").tag(0)
                }
                Text("Idle locking waits for your whole Mac to be inactive. Background locking fires while you keep working in other apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Lock when the device goes to sleep", isOn: $lockOnSleep)
                Toggle("Lock when the screensaver starts", isOn: $lockOnScreensaver)
            }
            Section("Clipboard") {
                Picker("Clear copied secrets after", selection: $clipboardClearSeconds) {
                    Text("30 seconds").tag(30)
                    Text("90 seconds").tag(90)
                    Text("3 minutes").tag(180)
                    Text("Never").tag(0)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .sheet(isPresented: $changePasswordShown) {
            ChangePasswordSheet(appState: appState)
        }
        .sheet(isPresented: $emergencyKitShown) {
            EmergencyKitSheet(appState: appState)
        }
    }
}

/// Reveals the Secret Key and re-saves the Emergency Kit, gated behind
/// Touch ID or the account password (like 1Password's reveal flow).
struct EmergencyKitSheet: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var revealedKey: SecretKey?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Emergency Kit")
                .font(.title3.bold())

            if let revealedKey {
                revealed(revealedKey)
            } else {
                verify
            }
        }
        .padding(22)
        .frame(width: 420)
        .task {
            // Lead with Touch ID when it's enrolled and currently allowed.
            if appState.biometricUnlockAllowed {
                await verifyWithTouchID()
            }
        }
    }

    private var verify: some View {
        Group {
            Text("Verify it's you to reveal your Secret Key.")
                .font(.callout)
                .foregroundStyle(.secondary)

            SecureField("Account Password", text: $password, prompt: Text("Account password"))
                .textFieldStyle(.roundedBorder)
                .onSubmit { verifyWithPassword() }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if appState.biometricUnlockAllowed {
                    Button("Use Touch ID") {
                        Task { await verifyWithTouchID() }
                    }
                }
                Spacer()
                Button {
                    verifyWithPassword()
                } label: {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Verify")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty || isWorking)
            }
        }
    }

    private func revealed(_ key: SecretKey) -> some View {
        Group {
            Text("Anyone with your Secret Key and account password can read your data. Store the kit somewhere safe — you'll need it to set up a new device.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("SECRET KEY")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                HStack {
                    Text(key.formatted)
                        .font(.system(.callout, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        ClipboardManager.copy(key.formatted, concealed: true)
                        copied = true
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy Secret Key")
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

            HStack {
                Button("Save Emergency Kit…") {
                    guard let email = appState.account?.email else { return }
                    EmergencyKitPDF.save(email: email, secretKey: key, presentingWindow: NSApp.keyWindow)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func verifyWithPassword() {
        guard !password.isEmpty, !isWorking else { return }
        errorMessage = nil
        isWorking = true
        Task {
            if await appState.verifyAccountPassword(password) {
                reveal()
            } else {
                errorMessage = "The account password is incorrect."
            }
            isWorking = false
        }
    }

    private func verifyWithTouchID() async {
        if case .success = await BiometricUnlock.unlock(reason: "reveal your Secret Key") {
            reveal()
        }
    }

    private func reveal() {
        guard let account = appState.account,
              let key = KeychainStore.loadSecretKey(accountID: account.id) else {
            errorMessage = "The Secret Key isn't stored on this Mac's Keychain."
            return
        }
        revealedKey = key
    }
}

/// Change the account password: verify current, pick a strong new one.
struct ChangePasswordSheet: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var succeeded = false

    private var newScore: PasswordStrength.Score { PasswordStrength.score(newPassword) }

    private var formValid: Bool {
        !currentPassword.isEmpty
            && newPassword.count >= 10
            && newPassword == confirmPassword
            && newPassword != currentPassword
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Change Account Password")
                .font(.title3.bold())

            if succeeded {
                Label("Password changed.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Use the new password from the next unlock. Update the password line in your Emergency Kit if you wrote it down.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Text("Your Secret Key and your data stay the same — only the password changes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    SecureField("Current Password", text: $currentPassword, prompt: Text("Current password"))
                        .textFieldStyle(.roundedBorder)
                    SecureField("New Password", text: $newPassword, prompt: Text("New password (10+ characters)"))
                        .textFieldStyle(.roundedBorder)
                    if !newPassword.isEmpty {
                        StrengthBar(score: newScore)
                    }
                    SecureField("Confirm New Password", text: $confirmPassword, prompt: Text("Confirm new password"))
                        .textFieldStyle(.roundedBorder)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                HStack {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button {
                        change()
                    } label: {
                        if isWorking {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Change Password")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!formValid || isWorking)
                }
            }
        }
        .padding(22)
        .frame(width: 420)
    }

    private func change() {
        errorMessage = nil
        guard newScore >= .fair else {
            errorMessage = "That password is too weak to protect a vault. Add more words or characters."
            return
        }
        isWorking = true
        Task {
            do {
                try await appState.changeAccountPassword(current: currentPassword, new: newPassword)
                succeeded = true
            } catch AppState.PasswordChangeError.wrongCurrentPassword {
                errorMessage = "The current password is incorrect."
            } catch {
                errorMessage = "Password change failed: \(error.localizedDescription)"
            }
            isWorking = false
        }
    }
}

struct PrivacySettingsView: View {
    @AppStorage(SettingsKeys.watchtowerHIBPEnabled) private var hibpEnabled = true
    @AppStorage(SettingsKeys.richIconsEnabled) private var richIconsEnabled = true
    @State private var cacheCleared = false

    var body: some View {
        Form {
            Section("Watchtower") {
                Toggle("Check for vulnerable passwords", isOn: $hibpEnabled)
                Text("Uses the Have I Been Pwned range API. Only the first 5 characters of a local SHA-1 hash are ever sent — your passwords never leave this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Rich Icons") {
                Toggle("Show website icons", isOn: $richIconsEnabled)
                Text("Icons are fetched directly from each website (no third-party icon service sees your saved sites).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(cacheCleared ? "Icon Cache Cleared" : "Clear Icon Cache") {
                    Task {
                        await FaviconLoader.shared.clearCache()
                        cacheCleared = true
                    }
                }
                .disabled(cacheCleared)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

/// Per-browser native-messaging manifest install, so the 2Password
/// extension can reach the app.
struct BrowserSettingsView: View {
    @State private var refreshToken = 0
    @State private var installError: String?

    var body: some View {
        Form {
            Section("Browser Extension") {
                let browsers = BrowserIntegration.detected
                if browsers.isEmpty {
                    Text("No Chromium-based browsers were found on this Mac.")
                        .foregroundStyle(.secondary)
                }
                ForEach(browsers) { browser in
                    let status = BrowserIntegration.status(for: browser)
                    LabeledContent(browser.name) {
                        switch status {
                        case .installed:
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .labelStyle(.titleAndIcon)
                        case .stale, .notInstalled:
                            Button(status == .stale ? "Repair…" : "Install…") {
                                do {
                                    try BrowserIntegration.install(for: browser)
                                    installError = nil
                                } catch {
                                    installError = "Couldn't write the manifest for \(browser.name): \(error.localizedDescription)"
                                }
                                refreshToken += 1
                            }
                        }
                    }
                }
                if let installError {
                    Text(installError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Installing registers 2Password with the browser, then load the extension from the repository's BrowserExtension folder (chrome://extensions → Load unpacked). Pairing is confirmed with a verification code on first connect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .id(refreshToken)
    }
}

struct AdvancedSettingsView: View {
    let appState: AppState

    var body: some View {
        Form {
            Section("iCloud Sync") {
                if SyncController.hasCloudKitEntitlement {
                    Toggle("Sync with iCloud", isOn: Binding(
                        get: { appState.sync.syncEnabled },
                        set: { appState.sync.syncEnabled = $0 }
                    ))
                    LabeledContent("Status", value: syncStatusText)
                } else {
                    Text("iCloud sync requires building with the CloudKit entitlement (see README: sign into Xcode and switch to 2Password+CloudKit.entitlements).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Recently Deleted") {
                Text("Items in Recently Deleted are permanently removed after 30 days.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Coming Soon") {
                Text("Browser extension & autofill, passkeys, SSH agent, and item sharing have reserved extension points and can be added later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }

    private var syncStatusText: String {
        switch appState.sync.status {
        case .disabled: "Off"
        case .idle: "Up to date"
        case .syncing: "Syncing…"
        case .error(let message): "Error: \(message)"
        case .accountUnavailable: "iCloud account unavailable"
        }
    }
}
