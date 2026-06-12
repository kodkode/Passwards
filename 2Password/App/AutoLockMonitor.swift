import AppKit
import CoreGraphics

/// Watches for idle time, sleep, and screensaver, and asks the app to lock.
/// Idle detection uses CGEventSource (no Accessibility permission required).
final class AutoLockMonitor {
    var onShouldLock: (() -> Void)?

    private var timer: Timer?
    private var observers: [any NSObjectProtocol] = []

    var idleMinutes: Int {
        UserDefaults.standard.object(forKey: SettingsKeys.idleLockMinutes) as? Int ?? 10
    }
    var lockOnSleep: Bool {
        UserDefaults.standard.object(forKey: SettingsKeys.lockOnSleep) as? Bool ?? true
    }
    var lockOnScreensaver: Bool {
        UserDefaults.standard.object(forKey: SettingsKeys.lockOnScreensaver) as? Bool ?? true
    }
    /// Lock after 2Password has been in the background this many minutes
    /// (0 = never). Unlike idle, this fires while you're busy in another app.
    var backgroundMinutes: Int {
        UserDefaults.standard.object(forKey: SettingsKeys.lockWhenBackgroundMinutes) as? Int ?? 0
    }

    /// When the app last resigned active; nil while frontmost.
    private var backgroundSince: Date?

    func start() {
        stop()
        backgroundSince = NSApp.isActive ? nil : Date()
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.backgroundSince = Date() }
        }
        let becomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.backgroundSince = nil }
        }

        let sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.lockOnSleep else { return }
                self.onShouldLock?()
            }
        }
        let screensaverObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screensaver.didstart"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.lockOnScreensaver else { return }
                self.onShouldLock?()
            }
        }
        observers = [resignObserver, becomeActiveObserver, sleepObserver, screensaverObserver]
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        backgroundSince = nil
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
    }

    private func tick() {
        // System-wide idle (resets on any input, anywhere) — like 1Password's
        // "Lock after the computer is idle for".
        if idleMinutes > 0 {
            let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
            if idle >= Double(idleMinutes * 60) {
                onShouldLock?()
                return
            }
        }
        // Time spent in the background — fires even while you're active in
        // another app (e.g. your browser).
        if backgroundMinutes > 0, let since = backgroundSince,
           Date().timeIntervalSince(since) >= Double(backgroundMinutes * 60) {
            onShouldLock?()
        }
    }
}
