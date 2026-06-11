import SwiftUI
import TwoPasswordCore

/// The lock screen: brand-blue backdrop, centered lock mark, password field,
/// Touch ID affordance.
struct LockScreenView: View {
    let appState: AppState

    @State private var password = ""
    @State private var typedSecretKey = ""
    @State private var isUnlocking = false
    @State private var failed = false
    @State private var shake = 0
    @FocusState private var passwordFocused: Bool

    var body: some View {
        ZStack {
            Theme.heroGradient.ignoresSafeArea()
            VStack(spacing: 24) {
                AppIconImage(size: 96)
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                Text("2Password")
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
                }
            }
            .padding(48)
        }
        .frame(minWidth: 760, minHeight: 560)
        .task {
            passwordFocused = true
            // Offer Touch ID immediately on lock-screen appearance, like 1P8.
            if appState.biometricUnlockAllowed {
                _ = await appState.unlockWithTouchID()
            }
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

struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: 8 * sin(animatableData * .pi * 4), y: 0
        ))
    }
}
