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

    func start() {
        stop()
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkIdle() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

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
        observers = [sleepObserver, screensaverObserver]
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observers = []
    }

    private func checkIdle() {
        guard idleMinutes > 0 else { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if idle >= Double(idleMinutes * 60) {
            onShouldLock?()
        }
    }
}
