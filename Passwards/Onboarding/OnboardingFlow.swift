import SwiftUI
import PasswardsCore

/// Account creation: welcome → email + password → Secret Key & Emergency Kit
/// → Touch ID opt-in.
struct OnboardingFlow: View {
    let appState: AppState

    private enum Step {
        case welcome
        case credentials
        case secretKey
        case touchID
        case signIn
    }

    @State private var step: Step = .welcome
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var result: AppState.OnboardingResult?
    @State private var savedKitConfirmed = false

    var body: some View {
        ZStack {
            Theme.heroGradient.ignoresSafeArea()
            Group {
                switch step {
                case .welcome: welcome
                case .credentials: credentials
                case .secretKey: secretKey
                case .touchID: touchID
                case .signIn: signIn
                }
            }
            .frame(maxWidth: 460)
            .padding(40)
        }
        .frame(minWidth: 760, minHeight: 560)
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            AppIconImage(size: 110)
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
            Text("Welcome to Passwards")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)
            Text("The safest place for your passwords,\nbuilt just for your Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.8))
            Button {
                step = .credentials
            } label: {
                Text("Create Your Account")
                    .font(.headline)
                    .frame(maxWidth: 280)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(Theme.accentDeep)
            .padding(.top, 12)

            if SyncController.hasCloudKitEntitlement {
                Button("Sign in to an existing account") {
                    step = .signIn
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.8))
                .underline()
            }
        }
    }

    @State private var signInSecretKey = ""
    @State private var signInError: String?
    @State private var signInBusy = false

    private var signIn: some View {
        card {
            Text("Sign in")
                .font(.title2.bold())
            Text("Your vault will be downloaded from iCloud. You need the account password and the Secret Key from your Emergency Kit.")
                .font(.callout)
                .foregroundStyle(.secondary)

            SecureField("Account Password", text: $password, prompt: Text("Account password"))
                .textFieldStyle(.roundedBorder)
            TextField("Secret Key", text: $signInSecretKey, prompt: Text("A3-XXXXXX-XXXXXX-XXXXX-XXXXX-XXXXX-XXXXX"))
                .textFieldStyle(.roundedBorder)
                .font(.callout.monospaced())

            if let signInError {
                Text(signInError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Back") { step = .welcome }
                Spacer()
                Button {
                    performSignIn()
                } label: {
                    if signInBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Sign In")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty || signInSecretKey.isEmpty || signInBusy)
            }
        }
    }

    private func performSignIn() {
        signInBusy = true
        signInError = nil
        Task {
            do {
                guard let remote = try await SyncController.fetchRemoteAccount() else {
                    signInError = "No account found in this iCloud account. Create a new one instead."
                    signInBusy = false
                    return
                }
                try await appState.signInToExistingAccount(
                    remote: remote, password: password, typedSecretKey: signInSecretKey
                )
            } catch {
                signInError = "Sign-in failed. Check your password and Secret Key."
            }
            signInBusy = false
        }
    }

    private var passwordScore: PasswordStrength.Score { PasswordStrength.score(password) }

    private var credentials: some View {
        card {
            Text("Create your account")
                .font(.title2.bold())
            Text("Your account password protects everything. Make it long and memorable — it can never be recovered if forgotten.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                TextField("Email", text: $email, prompt: Text("you@example.com"))
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.username)
                SecureField("Account Password", text: $password, prompt: Text("Account password"))
                    .textFieldStyle(.roundedBorder)
                if !password.isEmpty {
                    StrengthBar(score: passwordScore)
                }
                SecureField("Confirm Password", text: $confirmPassword, prompt: Text("Confirm password"))
                    .textFieldStyle(.roundedBorder)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Back") { step = .welcome }
                Spacer()
                Button {
                    create()
                } label: {
                    if isCreating {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Continue")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!formValid || isCreating)
            }
        }
    }

    private var formValid: Bool {
        email.contains("@") && password.count >= 10 && password == confirmPassword
    }

    private func create() {
        errorMessage = nil
        guard passwordScore >= .fair else {
            errorMessage = "That password is too weak to protect a vault. Add more words or characters."
            return
        }
        isCreating = true
        Task {
            do {
                result = try await appState.createAccount(email: email, password: password)
                step = .secretKey
            } catch {
                errorMessage = "Account creation failed: \(error.localizedDescription)"
            }
            isCreating = false
        }
    }

    private var secretKey: some View {
        card {
            Text("Your Secret Key")
                .font(.title2.bold())
            Text("This key encrypts your data together with your password. It's stored in your Mac's Keychain — save the Emergency Kit in case you ever need to set up a new device.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let result {
                Text(result.secretKey.formatted)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                HStack {
                    Button {
                        ClipboardManager.copy(result.secretKey.formatted, concealed: true)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    Button {
                        EmergencyKitPDF.save(email: result.email, secretKey: result.secretKey, presentingWindow: NSApp.keyWindow)
                    } label: {
                        Label("Save Emergency Kit…", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Toggle("I've saved my Secret Key somewhere safe", isOn: $savedKitConfirmed)
                .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button("Continue") {
                    step = BiometricUnlock.isAvailable ? .touchID : .welcome
                    if !BiometricUnlock.isAvailable { appState.finishOnboarding() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!savedKitConfirmed)
            }
        }
    }

    private var touchID: some View {
        card {
            Image(systemName: "touchid")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity)
            Text("Unlock with Touch ID")
                .font(.title2.bold())
                .frame(maxWidth: .infinity)
            Text("Use your fingerprint to unlock Passwards quickly. Your account password is still required from time to time.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                Button("Not Now") { appState.finishOnboarding() }
                Spacer()
                Button("Enable Touch ID") {
                    Task {
                        if let masterKey = await appState.keyStore.masterKey {
                            try? BiometricUnlock.enroll(masterKey: masterKey)
                        }
                        appState.finishOnboarding()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18, content: content)
            .padding(28)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 24, y: 8)
    }
}
