import SwiftUI
import PasswardsCore
import PasswardsOrchestration

/// Owns the shared `AccountController` for the iOS app and translates SwiftUI
/// scene-phase changes into the auto-lock / biometric-prompt behavior the macOS
/// app gets from AppKit notifications.
@MainActor
final class IOSAppModel {
    let core: AccountController
    private let autoLock = IOSAutoLockService()
    private var backgroundedAt: Date?

    init() {
        core = AccountController(
            sync: SyncController(),
            autoLock: autoLock,
            pasteboard: IOSPasteboardService(),
            appGroupIdentifier: IOSAppGroup.identifier
        )
    }

    func boot() async {
        await core.boot()
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            backgroundedAt = Date()
        case .active:
            if let since = backgroundedAt {
                let minutes = UserDefaults.standard.object(forKey: SettingsKeys.lockWhenBackgroundMinutes) as? Int ?? 0
                if minutes == 0 || Date().timeIntervalSince(since) >= Double(minutes) * 60 {
                    autoLock.lockNow()
                }
                backgroundedAt = nil
            }
            core.promptBiometricIfAppropriate()
        default:
            break
        }
    }
}

@main
struct PasswardsiOSApp: App {
    @State private var model = IOSAppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            IOSRootView(core: model.core)
                .task { await model.boot() }
                .onChange(of: scenePhase) { _, phase in
                    model.scenePhaseChanged(phase)
                }
        }
    }
}
