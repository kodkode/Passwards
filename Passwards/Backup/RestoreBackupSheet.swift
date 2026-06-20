import SwiftUI
import PasswardsCore

/// Credentials + confirmation for restoring an encrypted backup. Reused by both
/// Settings (replace the current vault) and onboarding (fresh Mac). The
/// "replaces everything" warning only shows when an account already exists.
struct RestoreBackupSheet: View {
    let appState: AppState
    let fileData: Data
    let header: BackupFile
    @Environment(\.dismiss) private var dismiss

    @State private var useRecoveryCode = false
    @State private var password = ""
    @State private var secretKey = ""
    @State private var recoveryCode = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var newScore: PasswordStrength.Score { PasswordStrength.score(newPassword) }

    private var formValid: Bool {
        if useRecoveryCode {
            return !recoveryCode.isEmpty && newPassword.count >= 10 && newPassword == confirmPassword
        }
        return !password.isEmpty && !secretKey.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Restore from Backup")
                .font(.title3.bold())

            Text("Backup from **\(header.account.email)**, created \(header.createdAt.formatted(date: .abbreviated, time: .shortened)).")
                .font(.callout)
                .foregroundStyle(.secondary)

            if appState.account != nil {
                Label("This replaces everything on this Mac with the backup's contents.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            if useRecoveryCode {
                TextField("Recovery Code", text: $recoveryCode, prompt: Text("RC-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"))
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospaced())
                SecureField("New Password", text: $newPassword, prompt: Text("New password (10+ characters)"))
                    .textFieldStyle(.roundedBorder)
                if !newPassword.isEmpty {
                    StrengthBar(score: newScore)
                }
                SecureField("Confirm New Password", text: $confirmPassword, prompt: Text("Confirm new password"))
                    .textFieldStyle(.roundedBorder)
            } else {
                SecureField("Account Password", text: $password, prompt: Text("Account password"))
                    .textFieldStyle(.roundedBorder)
                TextField("Secret Key", text: $secretKey, prompt: Text("A3-XXXXXX-XXXXXX-XXXXX-XXXXX-XXXXX-XXXXX"))
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospaced())
            }

            Button(useRecoveryCode ? "Use account password & Secret Key instead" : "Use a recovery code instead") {
                useRecoveryCode.toggle()
                errorMessage = nil
            }
            .buttonStyle(.link)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    restore()
                } label: {
                    if isWorking { ProgressView().controlSize(.small) } else { Text("Restore") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!formValid || isWorking)
            }
        }
        .padding(22)
        .frame(width: 460)
    }

    private func restore() {
        errorMessage = nil
        if useRecoveryCode, newScore < .fair {
            errorMessage = "That password is too weak to protect a vault. Add more words or characters."
            return
        }
        isWorking = true
        Task {
            do {
                if useRecoveryCode {
                    try await appState.restoreBackup(fileData: fileData, recoveryCode: recoveryCode, newPassword: newPassword)
                } else {
                    try await appState.restoreBackup(fileData: fileData, password: password, typedSecretKey: secretKey)
                }
                dismiss()
            } catch AppState.BackupRestoreError.wrongCredentials {
                errorMessage = useRecoveryCode
                    ? "That recovery code didn't work. Check it and try again."
                    : "Incorrect password or Secret Key."
            } catch {
                errorMessage = "Restore failed: \(error.localizedDescription)"
            }
            isWorking = false
        }
    }
}
