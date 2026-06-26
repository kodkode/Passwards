import SwiftUI
import PasswardsOrchestration
import AppKit
import PasswardsCore

/// Entry point: the same binary is either the GUI app or a headless
/// native-messaging host. Chromium browsers launch the manifest's binary
/// with the extension origin as the argument (a manifest cannot pass custom
/// flags), so the origin IS the host-mode signal; `--browser-host` remains
/// for manual testing.
@main
enum Boot {
    static func main() {
        let arguments = CommandLine.arguments.dropFirst()
        if arguments.contains("--browser-host")
            || arguments.contains(where: { $0.hasPrefix("chrome-extension://") }) {
            BrowserHostMode.run()
        }
        // A recognized first-argument subcommand runs the CLI instead of the GUI.
        if let first = arguments.first, CLIMode.commands.contains(first) {
            CLIMode.run(Array(arguments))
        }
        PasswardsApp.main()
    }
}

struct PasswardsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @State private var quickAccess: QuickAccessController?
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @AppStorage(SettingsKeys.theme) private var theme = "system"

    var body: some Scene {
        Window("Passwards", id: "main") {
            RootView(appState: appState)
                .preferredColorScheme(theme == "light" ? .light : theme == "dark" ? .dark : nil)
                .background(WindowConfigurator())
                .task {
                    await appState.bootstrap()
                    if quickAccess == nil {
                        quickAccess = QuickAccessController(appState: appState)
                    }
                }
        }
        // 1P8-style window: no title text, standard-height unified toolbar over
        // the content area, sidebar running full-height with the traffic lights
        // inside it. The sidebar uses macOS's native `.sidebar` material — but
        // that's behind-window vibrancy, so it only frosts when the window is
        // non-opaque. WindowConfigurator (on RootView) sets isOpaque=false with
        // a clear backing so the desktop shows through the sidebar, exactly like
        // 1Password 8, Finder, and Mail. The content columns paint their own
        // opaque backgrounds, so only the sidebar frosts.
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Lock Passwards") {
                    appState.lock()
                }
                .keyboardShortcut("l", modifiers: [.shift, .command])
                .disabled(appState.phase != .unlocked)

                Button("Quick Access") {
                    quickAccess?.toggle()
                }
            }
            // The items must always be present (disabled when locked), not gated
            // behind an `if` — a CommandGroup that starts empty at launch never
            // makes SwiftUI create the File menu for this single-`Window` scene,
            // and unlocking doesn't retroactively add it. Always-present content
            // keeps the File menu rendered, with the items greyed out until unlock.
            CommandGroup(replacing: .importExport) {
                Button("Import…") {
                    if let store = appState.vaultStore { ImportExport.importOnePux(appState: appState, store: store) }
                }
                .disabled(appState.phase != .unlocked)
                Button("Import from CSV…") {
                    if let store = appState.vaultStore { ImportExport.importCSV(appState: appState, store: store) }
                }
                .disabled(appState.phase != .unlocked)
                Divider()
                Button("Export Logins as CSV…") {
                    if let store = appState.vaultStore { ImportExport.exportCSV(appState: appState, store: store) }
                }
                .disabled(appState.phase != .unlocked)
                Button("Export All Items as JSON…") {
                    if let store = appState.vaultStore { ImportExport.exportJSON(appState: appState, store: store) }
                }
                .disabled(appState.phase != .unlocked)
                Divider()
                Button("Save Encrypted Backup…") {
                    Backup.saveBackup(appState: appState)
                }
                .disabled(appState.phase != .unlocked)
            }
            CommandGroup(replacing: .help) {
                HelpMenuItems()
            }
        }

        Window("Passwards Help", id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsScene(appState: appState)
        }

        MenuBarExtra("Passwards", systemImage: "lock.shield.fill", isInserted: $showMenuBarExtra) {
            Button("Open Passwards") {
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
            Button("Quit Passwards") {
                NSApp.terminate(nil)
            }
        }
    }
}

/// The "Help" menu: opens the in-app guide window. (Replaces the default empty
/// macOS Help menu.)
private struct HelpMenuItems: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Passwards Help") {
            openWindow(id: "help")
        }
        .keyboardShortcut("?", modifiers: .command)
    }
}

struct RootView: View {
    let appState: AppState

    var body: some View {
        switch appState.phase {
        case .loading:
            // The window is non-opaque (see WindowConfigurator), so every phase
            // must paint its own backdrop or the desktop bleeds through.
            ZStack {
                Theme.detailBackground.ignoresSafeArea()
                ProgressView()
            }
            .frame(minWidth: 760, minHeight: 560)
        case .onboarding:
            OnboardingFlow(appState: appState)
        case .databaseError:
            DatabaseErrorView(appState: appState)
        case .locked:
            LockScreenView(appState: appState)
        case .unlocked:
            MainWindow(appState: appState)
                .frame(minWidth: 900, minHeight: 560)
        }
    }
}

/// Makes the main window non-opaque so the sidebar's native behind-window
/// `.sidebar` material can sample the desktop and frost, like 1Password 8,
/// Finder, and Mail. `window` is nil while `makeNSView` runs, so configuration
/// hops to the next runloop and repeats in `updateNSView` so the first
/// appearance isn't missed. Only the sidebar shows through — the item-list and
/// detail columns paint their own opaque backgrounds.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.configure(nsView.window) }
    }

    private static func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
    }
}
