import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Capture-blocking can be bypassed in DEBUG builds only, so the developer
    /// workflow of screenshot-verifying UI changes works. Release builds always
    /// block capture, like 1Password.
    static var captureAllowed: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["TWOPW_ALLOW_CAPTURE"] == "1"
        #else
        false
        #endif
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Block screen capture of every window, like 1Password. A launch-time
        // sweep alone misses windows created later (Settings, the Emergency Kit
        // / Secret Key sheet, Large Type, the change-password sheet), which is
        // exactly where the most sensitive material is shown — so also re-sweep
        // whenever any window gains focus. Default-deny: a window added in the
        // future is protected automatically.
        if !Self.captureAllowed {
            protectAllWindowsFromCapture()
            NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.protectAllWindowsFromCapture()
            }
        }
        // CKSyncEngine listens for CloudKit pushes once the app registers.
        if SyncController.hasCloudKitEntitlement {
            NSApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Excludes every current app window from screen capture / screen sharing
    /// (`NSWindow.sharingType = .none`). Cheap to run repeatedly — a handful of
    /// windows — and idempotent.
    private func protectAllWindowsFromCapture() {
        guard !Self.captureAllowed else { return }
        for window in NSApp.windows where window.sharingType != .none {
            window.sharingType = .none
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
