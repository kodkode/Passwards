import SwiftUI
import PasswardsCore

/// The lock screen, matched to 1Password 8: a dark two-tone backdrop that mirrors
/// the unlocked sidebar/content split, the app mark straddling the divider, the
/// account avatar, and a dark inline password field with a reveal eye + arrow submit.
struct LockScreenView: View {
    let appState: AppState

    // The sidebar/content divider position; the app mark is centered on it.
    private let dividerX: CGFloat = 240
    private let fieldWidth: CGFloat = 330

    @State private var password = ""
    @State private var typedSecretKey = ""
    @State private var revealPassword = false
    @State private var isUnlocking = false
    @State private var failed = false
    @State private var shake = 0
    @State private var showRecover = false
    @FocusState private var passwordFocused: Bool
    @FocusState private var secretKeyFocused: Bool

    // 1P8 dark surfaces for the locked window.
    private let leftTone = Color(.sRGB, red: 0x2A / 255, green: 0x2A / 255, blue: 0x2E / 255)
    private let rightTone = Color(.sRGB, red: 0x22 / 255, green: 0x23 / 255, blue: 0x27 / 255)
    private let fieldFill = Color(.sRGB, red: 0x2B / 255, green: 0x2C / 255, blue: 0x32 / 255)
    private let focusColor = Color(.sRGB, red: 0.45, green: 0.50, blue: 0.92)

    var body: some View {
        ZStack {
            // Two-tone split mirroring the unlocked layout (sidebar | content).
            HStack(spacing: 0) {
                leftTone.frame(width: dividerX)
                rightTone
            }
            .ignoresSafeArea()

            GeometryReader { geo in
                HStack(alignment: .center, spacing: 40) {
                    AppIconImage(size: 124)
                        .shadow(color: .black.opacity(0.45), radius: 18, y: 10)

                    VStack(alignment: .leading, spacing: 14) {
                        DefaultAvatarView(size: 56)

                        if appState.needsSecretKeyEntry {
                            secretKeyField
                        }
                        passwordField

                        if failed {
                            Text(appState.needsSecretKeyEntry
                                 ? "Incorrect password or Secret Key."
                                 : "Incorrect password.")
                                .font(.callout)
                                .foregroundStyle(Color(.sRGB, red: 0.95, green: 0.40, blue: 0.40))
                        }

                        HStack(spacing: 16) {
                            if appState.biometricUnlockAllowed {
                                Button {
                                    Task { _ = await appState.unlockWithTouchID() }
                                } label: {
                                    Image(systemName: "touchid")
                                        .font(.system(size: 22))
                                        .foregroundStyle(focusColor)
                                }
                                .buttonStyle(.plain)
                                .help("Unlock with Touch ID")
                            }

                            if appState.hasRecoveryCode {
                                Button("Forgot password?") { showRecover = true }
                                    .buttonStyle(.plain)
                                    .font(.callout)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        .padding(.top, 2)
                    }
                    .frame(width: fieldWidth, alignment: .leading)
                }
                // Center the mark horizontally on the divider, vertically in the window.
                .padding(.leading, dividerX - 62)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .sheet(isPresented: $showRecover) {
            RecoverWithCodeSheet(appState: appState)
        }
        .task {
            passwordFocused = true
            // Touch ID is offered on app launch/activation (AppState observes
            // didBecomeActive), NOT on lock-screen appearance — otherwise a
            // manual lock would immediately re-prompt to unlock.
        }
    }

    private var passwordField: some View {
        HStack(spacing: 10) {
            Group {
                if revealPassword {
                    TextField("", text: $password, prompt: Text("Enter your password").foregroundStyle(.white.opacity(0.4)))
                } else {
                    SecureField("", text: $password, prompt: Text("Enter your password").foregroundStyle(.white.opacity(0.4)))
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .tint(.white)
            .focused($passwordFocused)
            .onSubmit(unlock)

            Button { revealPassword.toggle() } label: {
                Image(systemName: revealPassword ? "eye.slash" : "eye")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .help(revealPassword ? "Hide password" : "Show password")

            Rectangle().fill(.white.opacity(0.15)).frame(width: 1, height: 22)

            Button(action: unlock) {
                Group {
                    if isUnlocking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.right").font(.system(size: 14, weight: .semibold))
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(password.isEmpty ? .white.opacity(0.3) : focusColor)
            .disabled(password.isEmpty || isUnlocking)
        }
        .padding(.horizontal, 14)
        .frame(width: fieldWidth, height: 46)
        .background(fieldFill, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(passwordFocused ? focusColor : .white.opacity(0.10),
                              lineWidth: passwordFocused ? 1.5 : 1)
        }
        .modifier(ShakeEffect(animatableData: CGFloat(shake)))
    }

    private var secretKeyField: some View {
        TextField("", text: $typedSecretKey, prompt: Text("Secret Key").foregroundStyle(.white.opacity(0.4)))
            .textFieldStyle(.plain)
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(.white)
            .tint(.white)
            .focused($secretKeyFocused)
            .padding(.horizontal, 14)
            .frame(width: fieldWidth, height: 46)
            .background(fieldFill, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(secretKeyFocused ? focusColor : .white.opacity(0.10),
                                  lineWidth: secretKeyFocused ? 1.5 : 1)
            }
    }

    private func unlock() {
        guard !password.isEmpty, !isUnlocking else { return }
        isUnlocking = true
        failed = false
        Task {
            do {
                try await appState.unlock(
                    password: password,
                    typedSecretKey: typedSecretKey.isEmpty ? nil : typedSecretKey
                )
                password = ""
                typedSecretKey = ""
            } catch {
                failed = true
                withAnimation(.default) { shake += 1 }
            }
            isUnlocking = false
        }
    }
}

/// Recover access on this Mac when the password is forgotten: enter the recovery
/// code and choose a new password. On success the app unlocks and this sheet's
/// host (the lock screen) is replaced by the main window.
struct RecoverWithCodeSheet: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var score: PasswordStrength.Score { PasswordStrength.score(newPassword) }
    private var formValid: Bool {
        !code.isEmpty && newPassword.count >= 10 && newPassword == confirmPassword
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recover with Recovery Code")
                .font(.title3.bold())
            Text("Enter your recovery code and choose a new account password. Your Secret Key is restored automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("Recovery Code", text: $code, prompt: Text("RC-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"))
                .textFieldStyle(.roundedBorder)
                .font(.callout.monospaced())
            SecureField("New Password", text: $newPassword, prompt: Text("New password (10+ characters)"))
                .textFieldStyle(.roundedBorder)
            if !newPassword.isEmpty {
                StrengthBar(score: score)
            }
            SecureField("Confirm New Password", text: $confirmPassword, prompt: Text("Confirm new password"))
                .textFieldStyle(.roundedBorder)

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
                    recover()
                } label: {
                    if isWorking { ProgressView().controlSize(.small) } else { Text("Recover") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!formValid || isWorking)
            }
        }
        .padding(22)
        .frame(width: 440)
    }

    private func recover() {
        errorMessage = nil
        guard score >= .fair else {
            errorMessage = "That password is too weak to protect a vault. Add more words or characters."
            return
        }
        isWorking = true
        Task {
            do {
                try await appState.recoverWithCode(code, newPassword: newPassword)
                dismiss()
            } catch AppState.RecoveryError.invalidCode {
                errorMessage = "That recovery code didn't work. Check it and try again."
            } catch AppState.RecoveryError.noRecoveryConfigured {
                errorMessage = "This account doesn't have a recovery code set up."
            } catch {
                errorMessage = "Recovery failed: \(error.localizedDescription)"
            }
            isWorking = false
        }
    }
}

struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: 8 * sin(animatableData * .pi * 4), y: 0
        ))
    }
}
