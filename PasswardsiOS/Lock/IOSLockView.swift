import SwiftUI
import PasswardsCore
import PasswardsOrchestration

/// iOS lock screen, matched to 1Password 8: a dark backdrop, the app mark, and a
/// dark inline password field with a reveal eye + arrow submit, plus Face ID.
struct IOSLockView: View {
    let core: AccountController

    @State private var password = ""
    @State private var typedSecretKey = ""
    @State private var revealPassword = false
    @State private var isUnlocking = false
    @State private var failed = false
    @State private var shake = 0
    @FocusState private var passwordFocused: Bool

    var body: some View {
        ZStack {
            Theme.heroGradient.ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()
                AppMark(size: 96)
                Text("Passwards")
                    .font(Theme.title(28, .bold))
                    .foregroundStyle(.white)

                if core.needsSecretKeyEntry {
                    secretKeyField
                }
                passwordField

                if failed {
                    Text(core.needsSecretKeyEntry ? "Incorrect password or Secret Key." : "Incorrect password.")
                        .font(.callout)
                        .foregroundStyle(Color(.sRGB, red: 0.95, green: 0.40, blue: 0.40))
                }

                if core.biometricUnlockAllowed {
                    Button {
                        Task { _ = await core.unlockWithTouchID() }
                    } label: {
                        Label("Unlock with Face ID", systemImage: "faceid")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Theme.lockFocus)
                    }
                    .padding(.top, 4)
                }

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 28)
        }
        .task { passwordFocused = true }
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
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .foregroundStyle(.white)
            .tint(.white)
            .focused($passwordFocused)
            .onSubmit(unlock)

            Button { revealPassword.toggle() } label: {
                Image(systemName: revealPassword ? "eye.slash" : "eye")
                    .foregroundStyle(.white.opacity(0.55))
            }

            Rectangle().fill(.white.opacity(0.15)).frame(width: 1, height: 22)

            Button(action: unlock) {
                if isUnlocking {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "arrow.right").fontWeight(.semibold)
                }
            }
            .foregroundStyle(password.isEmpty ? .white.opacity(0.3) : Theme.lockFocus)
            .disabled(password.isEmpty || isUnlocking)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Theme.lockField, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(passwordFocused ? Theme.lockFocus : .white.opacity(0.10),
                              lineWidth: passwordFocused ? 1.5 : 1)
        }
        .modifier(ShakeEffect(animatableData: CGFloat(shake)))
    }

    private var secretKeyField: some View {
        TextField("", text: $typedSecretKey, prompt: Text("Secret Key").foregroundStyle(.white.opacity(0.4)))
            .font(Theme.mono(15))
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .foregroundStyle(.white)
            .tint(.white)
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Theme.lockField, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.10), lineWidth: 1)
            }
    }

    private func unlock() {
        guard !password.isEmpty, !isUnlocking else { return }
        isUnlocking = true
        failed = false
        Task {
            do {
                try await core.unlock(password: password, typedSecretKey: typedSecretKey.isEmpty ? nil : typedSecretKey)
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

struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 4), y: 0))
    }
}
