import SwiftUI
import PasswardsOrchestration

/// Root view: switches on the shared `AccountController` phase, like macOS `RootView`.
struct IOSRootView: View {
    let model: IOSAppModel
    private var core: AccountController { model.core }

    var body: some View {
        switch core.phase {
        case .loading:
            ZStack {
                Theme.lockBackdrop.ignoresSafeArea()
                ProgressView().tint(.white)
            }
        case .onboarding:
            IOSOnboardingView(core: core)
        case .databaseError:
            IOSDatabaseErrorView(core: core)
        case .locked:
            IOSLockView(core: core)
        case .unlocked:
            IOSHomeView(vault: model.vault)
        }
    }
}

/// Minimal vault-error screen (retry). Mirrors the macOS DatabaseErrorView's
/// safe stance — never offers to create a fresh account over an existing vault.
private struct IOSDatabaseErrorView: View {
    let core: AccountController

    var body: some View {
        ZStack {
            Theme.lockBackdrop.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.yellow)
                Text("Vault Unavailable")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text(core.bootstrapError ?? "The vault could not be opened.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    Task { await core.retryOpeningVault() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .padding(.top, 8)
            }
            .padding(40)
        }
    }
}
