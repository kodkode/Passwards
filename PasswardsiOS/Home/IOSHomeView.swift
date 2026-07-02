import SwiftUI
import PasswardsCore
import PasswardsOrchestration

enum IOSTab: Hashable { case vault, generator, security, settings }

/// The unlocked shell: the 4-tab bar (Stitch) — Vault, Generator, Security
/// (Watchtower), Settings. Loads the vault + runs Watchtower on appear.
struct IOSHomeView: View {
    let vault: IOSVaultModel
    let watchtower: IOSWatchtowerModel
    @State private var selectedTab: IOSTab = .vault
    private var core: AccountController { vault.core }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Vault", systemImage: "lock.fill", value: IOSTab.vault) {
                IOSVaultHomeView(vault: vault, watchtower: watchtower, selectedTab: $selectedTab)
            }
            Tab("Generator", systemImage: "key.fill", value: IOSTab.generator) {
                NavigationStack { IOSGeneratorView() }
            }
            Tab("Security", systemImage: "checkmark.shield.fill", value: IOSTab.security) {
                IOSSecurityView(watchtower: watchtower, vault: vault)
            }
            Tab("Settings", systemImage: "gearshape.fill", value: IOSTab.settings) {
                NavigationStack { IOSSettingsView(vault: vault) }
            }
        }
        .tint(Theme.accent)
        .task {
            await vault.load()
            // Reload list + re-audit when CloudKit delivers changes; kick a sync now.
            core.sync.onRemoteChanges = { [weak vault, weak watchtower] in
                Task { await vault?.load(); await watchtower?.run() }
            }
            core.sync.kick()
            await watchtower.run()
        }
    }
}

/// Settings (Stitch "Settings (Dark)"): profile row, Security, Appearance, Data
/// sections, and a Lock Application button.
struct IOSSettingsView: View {
    let vault: IOSVaultModel
    private var core: AccountController { vault.core }

    @State private var faceIDOn = BiometricUnlock.isEnrolled
    @State private var faceIDError: String?
    @AppStorage(IOSAppearance.storageKey) private var appearanceRaw = IOSAppearance.system.rawValue

    private var appearance: Binding<IOSAppearance> {
        Binding(get: { IOSAppearance(rawValue: appearanceRaw) ?? .system },
                set: { appearanceRaw = $0.rawValue })
    }

    var body: some View {
        List {
            // Profile
            Section {
                HStack(spacing: 16) {
                    AppMark(size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(core.account?.email ?? "Your Account")
                            .font(Theme.title(20, .semibold)).foregroundStyle(Theme.primaryLabel).lineLimit(1)
                        Text("Passwards account").font(Theme.text(14)).foregroundStyle(Theme.labelDim)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
                .listRowBackground(Theme.surface)
            }

            // Security
            Section {
                if BiometricUnlock.isAvailable {
                    Toggle(isOn: $faceIDOn) {
                        rowLabel("Face ID Unlock", icon: "faceid", tint: Theme.link)
                    }
                    .tint(Theme.accent)
                    .onChange(of: faceIDOn) { _, on in setFaceID(on) }
                }
                Button { core.lock() } label: {
                    HStack {
                        rowLabel("Lock Now", icon: "lock.fill", tint: Theme.accent)
                        Spacer()
                    }
                }
            } header: { caps("Security") } footer: {
                if let faceIDError { Text(faceIDError).foregroundStyle(.orange) }
            }
            .listRowBackground(Theme.surface)

            // Appearance
            Section {
                Picker(selection: appearance) {
                    ForEach(IOSAppearance.allCases) { Text($0.label).tag($0) }
                } label: {
                    rowLabel("Theme", icon: "circle.lefthalf.filled", tint: Theme.accent)
                }
                .pickerStyle(.menu)
                .tint(Theme.labelDim)
            } header: { caps("Appearance") }
            .listRowBackground(Theme.surface)

            // Data
            Section {
                HStack {
                    rowLabel("Sync", icon: "arrow.triangle.2.circlepath", tint: Theme.accent)
                    Spacer()
                    Text(syncStatusText).font(Theme.text(15)).foregroundStyle(syncStatusColor)
                }
                HStack {
                    rowLabel("Vaults", icon: "folder.fill", tint: Theme.link)
                    Spacer()
                    Text("\(max(vault.vaults.count, 1))").font(Theme.text(15)).foregroundStyle(Theme.labelDim)
                }
            } header: { caps("Data") }
            .listRowBackground(Theme.surface)

            // Lock Application
            Section {
                Button { core.lock() } label: {
                    Text("Lock Application").font(Theme.text(16, .medium))
                        .foregroundStyle(Theme.danger).frame(maxWidth: .infinity)
                }
                .listRowBackground(Theme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Settings")
        .tint(Theme.accent)
    }

    private func rowLabel(_ text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(tint)
                .frame(width: 30, height: 30).background(Theme.surfaceHigh, in: Circle())
            Text(text).font(Theme.text(16)).foregroundStyle(Theme.primaryLabel)
        }
    }

    private func caps(_ text: String) -> some View {
        Text(text.uppercased()).font(Theme.caps(11)).tracking(0.5).foregroundStyle(Theme.labelDim)
    }

    private var syncStatusText: String {
        switch core.sync.status {
        case .disabled: "Off"
        case .idle: "Up to date"
        case .syncing: "Syncing…"
        case .error(let m): m
        case .accountUnavailable: "iCloud unavailable"
        }
    }
    private var syncStatusColor: Color {
        switch core.sync.status {
        case .idle: Theme.accent
        case .syncing: Theme.link
        case .error, .accountUnavailable: .orange
        case .disabled: Theme.labelDim
        }
    }

    private func setFaceID(_ on: Bool) {
        faceIDError = nil
        Task {
            if on {
                guard let masterKey = await core.keyStore.masterKey else {
                    faceIDOn = false; faceIDError = "Unlock first, then enable Face ID."; return
                }
                do { try BiometricUnlock.enroll(masterKey: masterKey) }
                catch { faceIDOn = false; faceIDError = "Couldn't enable Face ID: \(error.localizedDescription)" }
            } else {
                BiometricUnlock.disable()
            }
        }
    }
}
