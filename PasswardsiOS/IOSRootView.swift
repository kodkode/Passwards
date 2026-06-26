import SwiftUI
import PasswardsOrchestration

/// Root view: switches on the shared `AccountController` phase, exactly like the
/// macOS `RootView`. The per-phase screens are placeholders for now (Phase 1a);
/// the real lock/onboarding/items UI lands in the following steps.
struct IOSRootView: View {
    let core: AccountController

    var body: some View {
        switch core.phase {
        case .loading:
            ProgressView()
        case .onboarding:
            IOSPhasePlaceholder(symbol: "person.crop.circle.badge.plus",
                                title: "Welcome to Passwards",
                                subtitle: "Onboarding & sign-in coming next.")
        case .databaseError:
            IOSPhasePlaceholder(symbol: "exclamationmark.triangle.fill",
                                title: "Vault Unavailable",
                                subtitle: core.bootstrapError ?? "The vault could not be opened.")
        case .locked:
            IOSPhasePlaceholder(symbol: "lock.fill",
                                title: "Locked",
                                subtitle: "Lock screen (Face ID + password) coming next.")
        case .unlocked:
            IOSPhasePlaceholder(symbol: "checkmark.seal.fill",
                                title: "Unlocked",
                                subtitle: "Items · Generator · Settings coming next.")
        }
    }
}

private struct IOSPhasePlaceholder: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text(title).font(.title2.bold())
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}
