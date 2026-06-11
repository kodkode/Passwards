import SwiftUI
import TwoPasswordCore

@main
struct TwoPasswordApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @State private var quickAccess: QuickAccessController?

    var body: some Scene {
        Window("2Password", id: "main") {
            RootView(appState: appState)
                .task {
                    await appState.bootstrap()
                    if quickAccess == nil {
                        quickAccess = QuickAccessController(appState: appState)
                    }
                }
        }
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
        }

        MenuBarExtra("2Password", systemImage: "lock.shield.fill") {
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
