import SwiftUI
import TwoPasswordCore

@main
struct TwoPasswordApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @State private var quickAccess: QuickAccessController?
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @AppStorage(SettingsKeys.theme) private var theme = "system"

    var body: some Scene {
        Window("2Password", id: "main") {
            RootView(appState: appState)
                .preferredColorScheme(theme == "light" ? .light : theme == "dark" ? .dark : nil)
                .task {
                    await appState.bootstrap()
                    if quickAccess == nil {
                        quickAccess = QuickAccessController(appState: appState)
                    }
                }
        }
        // 1P8-style window: no title text, standard-height unified toolbar over
        // the content area, sidebar running full-height with the traffic lights
        // inside it. The sidebar keeps macOS's native translucent material —
        // that's exactly what 1Password 8 uses.
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Lock 2Password") {
                    appState.lock()
                }
                .keyboardShortcut("l", modifiers: [.shift, .command])
                .disabled(appState.phase != .unlocked)

                Button("Quick Access") {
                    quickAccess?.toggle()
                }
            }
            CommandGroup(replacing: .importExport) {
                if appState.phase == .unlocked, let store = appState.vaultStore {
                    Button("Import from 1Password (.1pux)…") {
                        ImportExport.importOnePux(appState: appState, store: store)
                    }
                    Button("Import from CSV…") {
                        ImportExport.importCSV(appState: appState, store: store)
                    }
                    Divider()
                    Button("Export Logins as CSV…") {
                        ImportExport.exportCSV(appState: appState, store: store)
                    }
                    Button("Export All Items as JSON…") {
                        ImportExport.exportJSON(appState: appState, store: store)
                    }
                }
            }
        }

        Settings {
            SettingsScene(appState: appState)
        }

        MenuBarExtra("2Password", systemImage: "lock.shield.fill", isInserted: $showMenuBarExtra) {
            Button("Open 2Password") {
                NSApp.activate()
                NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            }
            Button("Quick Access  ⇧⌘Space") {
                quickAccess?.toggle()
            }
            Divider()
            Button("Lock  ⇧⌘L") {
                appState.lock()
            }
            .disabled(appState.phase != .unlocked)
            Divider()
            Button("Quit 2Password") {
                NSApp.terminate(nil)
            }
        }
    }
}

struct RootView: View {
    let appState: AppState

    var body: some View {
        switch appState.phase {
        case .loading:
            ProgressView()
                .frame(minWidth: 760, minHeight: 560)
        case .onboarding:
            OnboardingFlow(appState: appState)
        case .locked:
            LockScreenView(appState: appState)
        case .unlocked:
            MainWindow(appState: appState)
                .frame(minWidth: 900, minHeight: 560)
        }
    }
}
