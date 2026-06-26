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
        .task { await vault.load() }
    }
}

private struct IOSSettingsView: View {
    let core: AccountController

    var body: some View {
        List {
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
}
