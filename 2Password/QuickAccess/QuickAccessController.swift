import AppKit
import SwiftUI
import KeyboardShortcuts
import TwoPasswordCore

extension KeyboardShortcuts.Name {
    static let toggleQuickAccess = Self("toggleQuickAccess", default: .init(.space, modifiers: [.command, .shift]))
    static let lockApp = Self("lockApp", default: .init(.l, modifiers: [.command, .shift]))
}

/// Floating, non-activating Quick Access panel (⇧⌘Space): summon over any
/// app, search, copy credentials without stealing focus from the front app.
final class QuickAccessController {
    private var panel: QuickAccessPanel?
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        KeyboardShortcuts.onKeyUp(for: .toggleQuickAccess) { [weak self] in
            self?.toggle()
        }
        KeyboardShortcuts.onKeyUp(for: .lockApp) { [weak self] in
            self?.appState.lock()
            self?.hide()
        }
    }

    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let panel = ensurePanel()
        panel.center()
        // Position slightly above center, Spotlight-style.
        if let screen = NSScreen.main {
            var frame = panel.frame
            frame.origin.y = screen.visibleFrame.midY + screen.visibleFrame.height * 0.12
            panel.setFrameOrigin(frame.origin)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> QuickAccessPanel {
        if let panel { return panel }
        let panel = QuickAccessPanel(appState: appState, onDismiss: { [weak self] in self?.hide() })
        self.panel = panel
        return panel
    }
}

final class QuickAccessPanel: NSPanel {
    init(appState: AppState, onDismiss: @escaping () -> Void) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        if !AppDelegate.captureAllowed {
            sharingType = .none
        }
        animationBehavior = .utilityWindow

        let view = QuickAccessView(appState: appState, dismiss: onDismiss)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = contentRect(forFrameRect: frame)
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}
