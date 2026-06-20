import SwiftUI
import PasswardsCore

/// The lock screen: brand-blue backdrop, centered lock mark, password field,
/// Touch ID affordance.
struct LockScreenView: View {
    let appState: AppState

    @State private var password = ""
    @State private var typedSecretKey = ""
    @State private var isUnlocking = false
    @State private var failed = false
    @State private var shake = 0
    @State private var showRecover = false
    @FocusState private var passwordFocused: Bool

    var body: some View {
        ZStack {
            Theme.heroGradient.ignoresSafeArea()
            VStack(spacing: 24) {
                AppIconImage(size: 96)
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                Text("Passwards")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                if let email = appState.account?.email {
                    Text(email)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                }

                VStack(spacing: 12) {
                    if appState.needsSecretKeyEntry {
                        TextField("Secret Key", text: $typedSecretKey, prompt: Text("A3-XXXXXX-XXXXXX-XXXXX-XXXXX-XXXXX-XXXXX").foregroundStyle(.gray))
                            .textFieldStyle(.plain)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.black)
                            .tint(Theme.accentDeep)
                            .padding(10)
                            .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 8))
                            .frame(width: 360)
                            .environment(\.colorScheme, .light)
                    }

                    SecureField("Account Password", text: $password, prompt: Text("Account password").foregroundStyle(.gray))
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(.black)
                        .tint(Theme.accentDeep)
                        .padding(10)
                        .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 8))
                        .frame(width: 300)
                        .environment(\.colorScheme, .light)
                        .focused($passwordFocused)
                        .onSubmit(unlock)
                        .modifier(ShakeEffect(animatableData: CGFloat(shake)))

                    if failed {
                        Text(appState.needsSecretKeyEntry
                             ? "Incorrect password or Secret Key."
                             : "Incorrect password.")
                            .font(.callout)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.red.opacity(0.8), in: Capsule())
                    }

                    Button(action: unlock) {
                        Group {
                            if isUnlocking {
                                ProgressView().controlSize(.small).tint(Theme.accentDeep)
                            } else {
                                Text("Unlock")
                            }
                        }
                        .font(.headline)
                        .frame(width: 120)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(Theme.accentDeep)
                    .disabled(password.isEmpty || isUnlocking)

                    if appState.biometricUnlockAllowed {
                        Button {
                            Task {
                                _ = await appState.unlockWithTouchID()
                            }
                        } label: {
                            Label("Unlock with Touch ID", systemImage: "touchid")
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                    }

                    if appState.hasRecoveryCode {
                        Button("Forgot password? Use your recovery code") {
                            showRecover = true
                        }
                        .buttonStyle(.plain)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                        .underline()
                        .padding(.top, 4)
                    }
                }
            }
            .padding(48)
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
