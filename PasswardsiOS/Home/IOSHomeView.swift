import SwiftUI
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

    var body: some View {
        List {
            Section("iCloud") {
                HStack {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    Text(syncStatusText)
                        .font(.callout)
                        .foregroundStyle(syncStatusColor)
                }
            }

            Section("Security") {
                Button {
                    core.lock()
                } label: {
                    Label("Lock Now", systemImage: "lock.fill")
                }
            }

            Section {
                Text("Watchtower, attachments, recovery, and backup settings are coming in a later step.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
