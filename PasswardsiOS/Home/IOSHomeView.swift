import SwiftUI
import PasswardsOrchestration

/// The unlocked shell: a bottom tab bar (1P8-iOS), with Items, Generator, and
/// Settings. For this vertical slice the Items/Generator screens are placeholders
/// (the full list/detail/editor + generator land next); Settings can lock the app
/// so the unlock ↔ lock cycle is exercisable end to end.
struct IOSHomeView: View {
    let core: AccountController

    var body: some View {
        TabView {
            Tab("Items", systemImage: "square.grid.2x2") {
                NavigationStack {
                    ContentUnavailableView {
                        Label("No Items Yet", systemImage: "key.fill")
                    } description: {
                        Text("Item list, detail, and editing are coming next.")
                    }
                    .navigationTitle("Items")
                }
            }

            Tab("Generator", systemImage: "dial.medium") {
                NavigationStack {
                    ContentUnavailableView {
                        Label("Password Generator", systemImage: "dial.medium")
                    } description: {
                        Text("Coming next.")
                    }
                    .navigationTitle("Generator")
                }
            }

            Tab("Settings", systemImage: "gearshape") {
                NavigationStack {
                    IOSSettingsView(core: core)
                        .navigationTitle("Settings")
                }
            }
        }
        .tint(Theme.accent)
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
