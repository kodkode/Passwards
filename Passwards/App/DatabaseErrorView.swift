import SwiftUI
import AppKit
import PasswardsCore

/// Shown when opening the on-disk vault fails (corruption, a locked file, a
/// transient disk error, or a failed migration). Deliberately offers NO
/// "create a new account" path: routing a recoverable open failure into
/// onboarding would let a fresh account overwrite the existing vault's key
/// material and orphan every stored item. The vault on disk is untouched —
/// the user can retry, restore from a backup, or quit and investigate.
struct DatabaseErrorView: View {
    let appState: AppState

    @State private var isRetrying = false
    @State private var restoreChoice: Backup.Chosen?
    @State private var showEraseConfirm = false

    var body: some View {
        ZStack {
            Theme.detailBackground.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.orange)

                Text("Couldn't open your vault")
                    .font(.system(size: 24, weight: .bold))

                Text("Your encrypted vault is still on this Mac and hasn't been changed. This is usually temporary — another copy of Passwards may be open, or the disk may be full. Try again, or restore from a backup.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = appState.bootstrapError {
                    Text(detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }

                HStack(spacing: 12) {
                    Button("Quit") { NSApp.terminate(nil) }

                    Button("Restore from Backup…") {
                        if let chosen = Backup.chooseBackupFile() { restoreChoice = chosen }
                    }
                    // Restore writes into the database, so it needs one that opened.
                    .disabled(appState.database == nil)

                    Button {
                        isRetrying = true
                        Task {
                            await appState.retryOpeningVault()
                            isRetrying = false
                        }
                    } label: {
                        if isRetrying {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Try Again")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRetrying)
                }
                .padding(.top, 4)

                // Last resort, deliberately de-emphasized and gated behind a
                // typed confirmation. Only for a genuinely unrecoverable vault
                // with no backup — everything below is permanently destroyed.
                Button("Erase & Start Over…", role: .destructive) {
                    showEraseConfirm = true
                }
                .buttonStyle(.link)
                .foregroundStyle(.red)
                .padding(.top, 10)
            }
            .frame(maxWidth: 440)
            .padding(40)
        }
        .frame(minWidth: 760, minHeight: 560)
        .sheet(item: $restoreChoice) { chosen in
            RestoreBackupSheet(appState: appState, fileData: chosen.data, header: chosen.file)
        }
        .sheet(isPresented: $showEraseConfirm) {
            EraseConfirmSheet(appState: appState)
        }
    }
}

/// Type-to-confirm gate for the irreversible "erase and start over" path. Kept
/// in its own sheet so it can't be triggered by a stray click, and steers the
/// user back to Restore if they have a backup.
private struct EraseConfirmSheet: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var confirmText = ""
    @State private var isErasing = false

    private var canErase: Bool { confirmText.trimmingCharacters(in: .whitespaces) == "ERASE" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Erase everything and start over", systemImage: "trash.fill")
                .font(.title3.bold())
                .foregroundStyle(.red)

            Text("This permanently deletes every item, attachment, and account detail stored on this Mac. **It cannot be undone.**")
                .fixedSize(horizontal: false, vertical: true)
            Text("If you have a backup or your account is in iCloud, cancel and choose **Restore from Backup** instead — that recovers your data.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Type ERASE to confirm")
                .font(.callout.weight(.medium))
            TextField("", text: $confirmText, prompt: Text("ERASE"))
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .disableAutocorrection(true)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(role: .destructive) {
                    isErasing = true
                    Task {
                        await appState.eraseVaultAndRestartOnboarding()
                        // The phase flips to .onboarding, swapping out RootView and
                        // this sheet; dismiss defensively in case it lingers.
                        dismiss()
                    }
                } label: {
                    if isErasing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Erase Everything")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!canErase || isErasing)
            }
        }
        .padding(22)
        .frame(width: 460)
    }
}
