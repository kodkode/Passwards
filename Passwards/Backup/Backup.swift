import AppKit
import SwiftUI
import PasswardsCore
import UniformTypeIdentifiers

/// File-panel flows for the encrypted `.pwbackup` backup. Creating a backup needs
/// only an unlocked app (it's sealed under the master key); restoring needs the
/// account password + Secret Key, or a recovery code (handled by RestoreBackupSheet).
enum Backup {
    static var fileType: UTType { UTType(filenameExtension: BackupArchive.fileExtension) ?? .data }

    /// A backup file the user picked, with its readable header decoded.
    struct Chosen: Identifiable {
        let id = UUID()
        let data: Data
        let file: BackupFile
    }

    /// Saves an encrypted backup of the whole vault (unlocked only).
    static func saveBackup(appState: AppState) {
        Task {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [fileType]
            panel.nameFieldStringValue = defaultFileName()

            // Only offer the recovery-code toggle when a code is actually active —
            // otherwise there's nothing to strip. A recovery code can open ANY
            // backup made while it was enabled, even after the code is rotated or
            // turned off (rotation can't reach already-exported files), so let the
            // user make a password-only backup that a future rotation covers.
            let recoveryActive = appState.hasRecoveryCode
            let toggle = NSButton(checkboxWithTitle: "Allow restoring this backup with a recovery code", target: nil, action: nil)
            toggle.state = .on
            toggle.toolTip = "If checked, anyone with this file and your recovery code can open it — even after you rotate or turn off recovery. Uncheck for a password-only backup."
            if recoveryActive {
                let label = NSTextField(wrappingLabelWithString: "Rotating or disabling a recovery code does not invalidate backups already exported while it was active.")
                label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
                label.textColor = .secondaryLabelColor
                let stack = NSStackView(views: [toggle, label])
                stack.orientation = .vertical
                stack.alignment = .leading
                stack.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
                stack.translatesAutoresizingMaskIntoConstraints = false
                label.widthAnchor.constraint(equalToConstant: 360).isActive = true
                panel.accessoryView = stack
            }
            panel.message = recoveryActive
                ? "This backup is encrypted. To restore it you'll need your account password + Secret Key (and, unless you uncheck the option below, a recovery code can also open it)."
                : "This backup is encrypted. To restore it you'll need your account password + Secret Key."

            guard panel.runModal() == .OK, let url = panel.url else { return }
            let includeRecovery = recoveryActive && toggle.state == .on
            do {
                let data = try await appState.makeBackupData(includeRecovery: includeRecovery)
                try data.write(to: url, options: .atomic)
                notify("Backup saved", "Saved to \(url.lastPathComponent). It's encrypted — keep it somewhere safe.")
            } catch {
                notify("Backup failed", error.localizedDescription)
            }
        }
    }

    /// Prompts for a `.pwbackup` file and decodes its header. Returns nil if the
    /// user cancels or the file isn't a readable backup.
    static func chooseBackupFile() -> Chosen? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [fileType]
        panel.message = "Choose a Passwards backup (.pwbackup)"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let data = try? Data(contentsOf: url), let file = try? BackupArchive.decode(data) else {
            notify("Couldn't read backup", "That file isn't a valid Passwards backup, or it was made by a newer version of the app.")
            return nil
        }
        return Chosen(data: data, file: file)
    }

    private static func defaultFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "Passwards Backup \(formatter.string(from: Date())).pwbackup"
    }

    static func notify(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
