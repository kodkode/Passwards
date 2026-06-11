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
    @AppStorage(SettingsKeys.lockOnSleep) private var lockOnSleep = true
    @AppStorage(SettingsKeys.lockOnScreensaver) private var lockOnScreensaver = true
    @AppStorage(SettingsKeys.requirePasswordAfterHours) private var requirePasswordAfterHours = 72
    @AppStorage(SettingsKeys.clipboardClearSeconds) private var clipboardClearSeconds = 90
    @State private var touchIDEnabled = BiometricUnlock.isEnrolled

    var body: some View {
        Form {
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
