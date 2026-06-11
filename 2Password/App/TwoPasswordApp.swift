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
            MainPlaceholderView(appState: appState)
        }
    }
}

/// Temporary stand-in until the Phase 3 three-pane main window.
struct MainPlaceholderView: View {
    let appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)
            Text("Vault unlocked")
                .font(.title.bold())
            Button("Lock") { appState.lock() }
        }
        .frame(minWidth: 760, minHeight: 560)
    }
}
