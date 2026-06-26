import SwiftUI
import PasswardsCore
import PasswardsOrchestration

/// The unlocked shell: a bottom tab bar (1P8-iOS) — Items, Generator, Settings.
struct IOSHomeView: View {
    let vault: IOSVaultModel
    private var core: AccountController { vault.core }

    var body: some View {
        TabView {
            Tab("Items", systemImage: "square.grid.2x2") {
                IOSItemListView(vault: vault)
            }

            Tab("Generator", systemImage: "dial.medium") {
                NavigationStack { IOSGeneratorView() }
            }

            Tab("Settings", systemImage: "gearshape") {
                NavigationStack {
                    IOSSettingsView(core: core)
                        .navigationTitle("Settings")
                }
            }
        }
        .tint(Theme.accent)
        .task {
            await vault.load()
            // CloudKit delivers items in the background (especially right after a
            // new-device sign-in); reload the list when a sync round finishes, and
            // kick one now to pull anything already queued. Mirrors macOS MainWindow.
            core.sync.onRemoteChanges = { [weak vault] in
                Task { await vault?.load() }
            }
            core.sync.kick()
        }
    }
}

private struct IOSSettingsView: View {
    let core: AccountController
    @State private var faceIDOn = BiometricUnlock.isEnrolled
    @State private var faceIDError: String?

    var body: some View {
        List {
            Section {
                HStack {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    Text(syncStatusText)
                        .font(Theme.text(15, .medium))
                        .foregroundStyle(syncStatusColor)
                }
            } header: { caps("iCloud") }
            .listRowBackground(Theme.surface)

            Section {
                if BiometricUnlock.isAvailable {
                    Toggle(isOn: $faceIDOn) {
                        Label("Unlock with Face ID", systemImage: "faceid")
                    }
                    .tint(Theme.accent)
                    .onChange(of: faceIDOn) { _, on in setFaceID(on) }
                }
                Button {
                    core.lock()
                } label: {
                    Label("Lock Now", systemImage: "lock.fill").foregroundStyle(.white)
                }
            } header: {
                caps("Security")
            } footer: {
                if let faceIDError {
                    Text(faceIDError).foregroundStyle(.orange)
                } else if BiometricUnlock.isAvailable {
                    Text("Re-enable Face ID on each new device. Your account password is still required from time to time.")
                        .foregroundStyle(Theme.labelDim)
                }
            }
            .listRowBackground(Theme.surface)

            Section {
                Text("Watchtower, attachments, recovery, and backup settings are coming in a later step.")
                    .font(.footnote)
                    .foregroundStyle(Theme.labelDim)
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .tint(Theme.accent)
    }

    private func caps(_ text: String) -> some View {
        Text(text.uppercased()).font(Theme.caps(11)).tracking(0.5).foregroundStyle(Theme.labelDim)
    }

    private func setFaceID(_ on: Bool) {
        faceIDError = nil
        Task {
            if on {
                guard let masterKey = await core.keyStore.masterKey else {
                    faceIDOn = false
                    faceIDError = "Unlock first, then enable Face ID."
                    return
                }
                do {
                    try BiometricUnlock.enroll(masterKey: masterKey)
                } catch {
                    faceIDOn = false
                    faceIDError = "Couldn't enable Face ID: \(error.localizedDescription)"
                }
            } else {
                BiometricUnlock.disable()
            }
        }
    }

    private var syncStatusText: String {
        switch core.sync.status {
        case .disabled: "Off"
        case .idle: "Up to date"
        case .syncing: "Syncing…"
        case .error(let message): message
        case .accountUnavailable: "iCloud unavailable"
        }
    }

    private var syncStatusColor: Color {
        switch core.sync.status {
        case .idle: .secondary
        case .syncing: Theme.accent
        case .error, .accountUnavailable: .orange
        case .disabled: .secondary
        }
    }
}
