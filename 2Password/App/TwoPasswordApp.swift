import SwiftUI
import TwoPasswordCore

@main
struct TwoPasswordApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        Window("2Password", id: "main") {
            RootView(appState: appState)
                .task {
                    await appState.bootstrap()
                }
        }
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Lock 2Password") {
                    appState.lock()
                }
                .keyboardShortcut("l", modifiers: [.shift, .command])
                .disabled(appState.phase != .unlocked)
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
