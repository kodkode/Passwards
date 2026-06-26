import UIKit
import PasswardsOrchestration

/// iOS App Group shared by the app and (later) the AutoFill extension. iOS app
/// groups must be `group.`-prefixed; the macOS app uses its own `<TeamID>.` group
/// — that's fine, App Group containers are per-device and never cross-sync (only
/// CloudKit does). The keychain group + iCloud container DO match macOS exactly.
enum IOSAppGroup {
    static let identifier = "group.com.michael.passwards"
}

/// iOS pasteboard adapter for the shared `PasteboardService` seam.
struct IOSPasteboardService: PasteboardService {
    func copy(_ value: String, concealed: Bool) {
        if concealed {
            // Keep secrets off other devices (no Universal Clipboard) and auto-expire.
            UIPasteboard.general.setItems(
                [["public.utf8-plain-text": value]],
                options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(90)]
            )
        } else {
            UIPasteboard.general.string = value
        }
    }

    func clearSecret() {
        UIPasteboard.general.items = []
    }
}

/// iOS auto-lock adapter. SwiftUI drives the actual scene-phase transitions (see
/// `IOSAppModel`); this just tracks whether locking is armed (i.e. unlocked) and
/// relays the lock request the controller wired into `onShouldLock`.
@MainActor
final class IOSAutoLockService: AutoLockService {
    var onShouldLock: (() -> Void)?
    private(set) var isArmed = false

    func start() { isArmed = true }
    func stop() { isArmed = false }

    /// Called by the app shell when returning to the foreground after being
    /// backgrounded longer than the configured threshold.
    func lockNow() { if isArmed { onShouldLock?() } }
}
