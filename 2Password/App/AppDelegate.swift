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
        // Block screen capture of vault windows, like 1Password.
        if !Self.captureAllowed {
            for window in NSApp.windows {
                window.sharingType = .none
            }
        }
        // CKSyncEngine listens for CloudKit pushes once the app registers.
        if SyncController.hasCloudKitEntitlement {
            NSApplication.shared.registerForRemoteNotifications()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
