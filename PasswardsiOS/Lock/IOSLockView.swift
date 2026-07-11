import SwiftUI
import PasswardsCore
import PasswardsOrchestration

/// iOS lock screen (playful): a centered brand block on the lavender background,
/// with a large Face ID button and a password fallback. Our real unlock is the
/// account master password (+ Secret Key when a new device needs it), not a PIN.
struct IOSLockView: View {
    let core: AccountController

    @State private var password = ""
    @State private var typedSecretKey = ""
    @State private var revealPassword = false
    @State private var showPassword = false
    @State private var isUnlocking = false
    @State private var failed = false
    @State private var shake = 0
    @FocusState private var passwordFocused: Bool

    private var faceIDMode: Bool { core.biometricUnlockAllowed && !showPassword && !core.needsSecretKeyEntry }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 14) {
                    AppMark(size: 92)
                    Text("Passwards").font(Theme.display(30, .semibold)).foregroundStyle(Theme.primaryLabel)
                    Text("You're back! Let's go").font(Theme.text(15)).foregroundStyle(Theme.label)
                }
                Spacer()
                Group { if faceIDMode { faceIDArea } else { passwordArea } }
                    .padding(.horizontal, 28)
                Spacer()
            }
        }
        .task {
            if !faceIDMode { passwordFocused = true }
        }
    }

    // MARK: Face ID

    private var faceIDArea: some View {
        VStack(spacing: 18) {
            Button {
                Task { _ = await core.unlockWithTouchID() }
            } label: {
                Image(systemName: "faceid").font(.system(size: 34, weight: .semibold)).foregroundStyle(Theme.accentText)
                    .frame(width: 74, height: 74).background(Theme.accent, in: Circle())
                    .shadow(color: Theme.accent.opacity(0.35), radius: 16, y: 8)
            }
            .buttonStyle(PressScale(scale: 0.92))
            Button("Enter Password Instead") { showPassword = true; passwordFocused = true }
                .font(Theme.text(15, .medium)).foregroundStyle(Theme.accent)
        }
    }

    // MARK: Password

    private var passwordArea: some View {
        VStack(spacing: 14) {
            if core.needsSecretKeyEntry { secretKeyField }
            passwordField
            if failed {
                Text(core.needsSecretKeyEntry ? "Incorrect password or Secret Key." : "Incorrect password.")
                    .font(Theme.text(14)).foregroundStyle(Theme.danger)
            }
            if core.biometricUnlockAllowed && !core.needsSecretKeyEntry {
                Button { showPassword = false; Task { _ = await core.unlockWithTouchID() } } label: {
                    Label("Use Face ID Instead", systemImage: "faceid").font(Theme.text(15, .medium))
                }
                .foregroundStyle(Theme.accent).padding(.top, 2)
            }
        }
    }

    private var passwordField: some View {
        HStack(spacing: 10) {
            Group {
                if revealPassword {
                    TextField("", text: $password, prompt: Text("Enter your password").foregroundStyle(Theme.label))
                } else {
                    SecureField("", text: $password, prompt: Text("Enter your password").foregroundStyle(Theme.label))
                }
            }
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .foregroundStyle(Theme.primaryLabel).tint(Theme.accent)
            .focused($passwordFocused).onSubmit(unlock).font(Theme.text(16))

            Button { revealPassword.toggle() } label: {
                Image(systemName: revealPassword ? "eye.slash" : "eye").foregroundStyle(Theme.label)
            }
            Rectangle().fill(Theme.cardBorder).frame(width: 1, height: 22)
            Button(action: unlock) {
                if isUnlocking { ProgressView() }
                else { Image(systemName: "arrow.right").fontWeight(.semibold) }
            }
            .foregroundStyle(password.isEmpty ? Theme.label : Theme.accent)
            .disabled(password.isEmpty || isUnlocking)
        }
        .padding(.horizontal, 16).frame(height: 54)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.rInput, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.rInput, style: .continuous)
                .strokeBorder(passwordFocused ? Theme.accent : Theme.cardBorder, lineWidth: passwordFocused ? 1.5 : 1)
        }
        .modifier(ShakeEffect(animatableData: CGFloat(shake)))
    }

    private var secretKeyField: some View {
        TextField("", text: $typedSecretKey, prompt: Text("Secret Key").foregroundStyle(Theme.label))
            .font(Theme.mono(15)).textInputAutocapitalization(.characters).autocorrectionDisabled()
            .foregroundStyle(Theme.primaryLabel).tint(Theme.accent)
            .padding(.horizontal, 16).frame(height: 54)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.rInput, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.rInput, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
    }

    private func unlock() {
        guard !password.isEmpty, !isUnlocking else { return }
        isUnlocking = true; failed = false
        Task {
            do {
                try await core.unlock(password: password, typedSecretKey: typedSecretKey.isEmpty ? nil : typedSecretKey)
                password = ""; typedSecretKey = ""
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
