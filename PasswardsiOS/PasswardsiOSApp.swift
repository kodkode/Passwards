import SwiftUI
import PasswardsCore
import PasswardsOrchestration

/// Owns the shared `AccountController` for the iOS app and translates SwiftUI
/// scene-phase changes into the auto-lock / biometric-prompt behavior the macOS
/// app gets from AppKit notifications.
@MainActor
final class IOSAppModel {
    let core: AccountController
    let vault: IOSVaultModel
    private let autoLock = IOSAutoLockService()
    private var backgroundedAt: Date?

    init() {
        let core = AccountController(
            sync: SyncController(),
            autoLock: autoLock,
            pasteboard: IOSPasteboardService(),
            appGroupIdentifier: IOSAppGroup.identifier
        )
        self.core = core
        let vault = IOSVaultModel(core: core)
        self.vault = vault
        // The decrypted summary cache lives in the vault model, so the controller
        // sheds/refreshes it on lock/restore.
        core.onVaultShouldClearSecrets = { [weak vault] in vault?.clearSecrets() }
        core.onVaultShouldRefresh = { [weak vault] in await vault?.refresh() }
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
            #if DEBUG
            if let preview = Self.screenshotPreview(model: model) {
                preview   // renders one screen directly (no bootstrap) for capture
            } else {
                liveRoot
            }
            #else
            liveRoot
            #endif
        }
    }

    private var liveRoot: some View {
        IOSRootView(model: model)
            .task { await model.boot() }
            .onChange(of: scenePhase) { _, phase in
                model.scenePhaseChanged(phase)
            }
    }

    #if DEBUG
    /// Renders a single screen for screenshot/design review when launched with
    /// `-uiPreview <name>`. Bypasses bootstrap so screens render with a fresh,
    /// empty controller. Debug-only.
    static func screenshotPreview(model: IOSAppModel) -> AnyView? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiPreview"), i + 1 < args.count else { return nil }
        let core = model.core
        let vault = model.vault
        let seeded = { vault.seedPreview(); return vault }
        switch args[i + 1] {
        case "welcome": return AnyView(IOSOnboardingView(core: core, initialStep: .welcome))
        case "credentials": return AnyView(IOSOnboardingView(core: core, initialStep: .credentials))
        case "lock": return AnyView(IOSLockView(core: core))
        case "home": return AnyView(IOSHomeView(vault: seeded()))
        case "list": return AnyView(IOSItemListView(vault: seeded()))
        case "detail": return AnyView(NavigationStack { IOSItemDetailView(vault: seeded(), itemID: "1") })
        case "editor": return AnyView(NavigationStack {
            IOSItemEditorView(vault: seeded(), original: vault.seededDetailItem, isNew: false, showsCancel: true, onClose: {})
        })
        case "picker": return AnyView(IOSCategoryPickerView(vault: seeded()))
        case "generator": return AnyView(NavigationStack { IOSGeneratorView() })
        default: return nil
        }
    }
    #endif
}
