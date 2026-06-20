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
            panel.message = "This backup is encrypted. To restore it you'll need your account password + Secret Key, or a recovery code."
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                let data = try await appState.makeBackupData()
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
