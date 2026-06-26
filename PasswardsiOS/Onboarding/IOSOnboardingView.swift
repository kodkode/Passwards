import SwiftUI
import UIKit
import CloudKit
import PasswardsCore
import PasswardsOrchestration

/// iOS account setup: welcome → email + password → Secret Key → Face ID, plus a
/// "sign in to an existing account" path that pulls the account from iCloud.
/// Mirrors the macOS onboarding copy/steps, rebuilt for iPhone (hero gradient,
/// card forms, large buttons).
struct IOSOnboardingView: View {
    let core: AccountController

    enum Step { case welcome, credentials, secretKey, faceID, signIn }

    @State private var step: Step

    init(core: AccountController, initialStep: Step = .welcome) {
        self.core = core
        _step = State(initialValue: initialStep)
    }
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var signInSecretKey = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var result: AccountController.OnboardingResult?
    @State private var savedKitConfirmed = false

    private var passwordScore: PasswordStrength.Score { PasswordStrength.score(password) }
    private var createValid: Bool { email.contains("@") && password.count >= 10 && password == confirmPassword }

    var body: some View {
        ZStack {
            Theme.heroGradient.ignoresSafeArea()
            ScrollView {
                Group {
                    switch step {
                    case .welcome: welcome
                    case .credentials: credentials
                    case .secretKey: secretKeyStep
                    case .faceID: faceIDStep
                    case .signIn: signIn
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: Welcome

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 40)
            AppMark(size: 96)
            Text("Welcome to Passwards")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("The safest place for your passwords,\nnow on your iPhone.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))

            VStack(spacing: 12) {
                Button {
                    step = .credentials
                } label: {
                    Text("Create Your Account").frame(maxWidth: .infinity)
                }
                .buttonStyle(HeroPrimaryButton())

                if SyncController.hasCloudKitEntitlement {
                    Button("Sign in to an existing account") { step = .signIn }
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.top, 4)
                }
            }
            .padding(.top, 12)
            Spacer(minLength: 20)
        }
    }

    // MARK: Create account

    private var credentials: some View {
        OnboardingCard(title: "Create your account",
                       subtitle: "Your account password protects everything. Make it long and memorable — it can never be recovered if forgotten.") {
            TextField("Email", text: $email, prompt: Text("you@example.com"))
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Divider()
            SecureField("Account Password", text: $password, prompt: Text("Account password"))
                .textContentType(.newPassword)
            if !password.isEmpty { StrengthBar(score: passwordScore) }
            Divider()
            SecureField("Confirm Password", text: $confirmPassword, prompt: Text("Confirm password"))
                .textContentType(.newPassword)

            errorText

            HStack {
                Button("Back") { step = .welcome }.tint(.secondary)
                Spacer()
                Button(action: create) {
                    if isWorking { ProgressView() } else { Text("Continue").bold() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(!createValid || isWorking)
            }
        }
    }

    private func create() {
        errorMessage = nil
        guard passwordScore >= .fair else {
            errorMessage = "That password is too weak to protect a vault. Add more words or characters."
            return
        }
        isWorking = true
        Task {
            do {
                result = try await core.createAccount(email: email, password: password)
                step = .secretKey
            } catch {
                errorMessage = "Account creation failed: \(error.localizedDescription)"
            }
            isWorking = false
        }
    }

    // MARK: Secret Key

    private var secretKeyStep: some View {
        OnboardingCard(title: "Your Secret Key",
                       subtitle: "This key encrypts your data together with your password. It's kept in this iPhone's Keychain — save it somewhere safe in case you set up a new device.") {
            if let result {
                Text(result.secretKey.formatted)
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = result.secretKey.formatted
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    ShareLink(item: result.secretKey.formatted) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
                .font(.callout)
            }

            Toggle("I've saved my Secret Key somewhere safe", isOn: $savedKitConfirmed)
                .tint(Theme.accent)
                .font(.callout)

            HStack {
                Spacer()
                Button("Continue") {
                    if BiometricUnlock.isAvailable {
                        step = .faceID
                    } else {
                        core.finishOnboarding()
                    }
                }
                .bold()
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(!savedKitConfirmed)
            }
        }
    }

    // MARK: Face ID

    private var faceIDStep: some View {
        OnboardingCard(title: "", subtitle: "") {
            VStack(spacing: 14) {
                Image(systemName: "faceid")
                    .font(.system(size: 52))
                    .foregroundStyle(Theme.accent)
                Text("Unlock with Face ID")
                    .font(.title2.bold())
                Text("Use Face ID to unlock Passwards quickly. Your account password is still required from time to time.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            HStack {
                Button("Not Now") { core.finishOnboarding() }.tint(.secondary)
                Spacer()
                Button("Enable Face ID") {
                    Task {
                        if let masterKey = await core.keyStore.masterKey {
                            try? BiometricUnlock.enroll(masterKey: masterKey)
                        }
                        core.finishOnboarding()
                    }
                }
                .bold()
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
        }
    }

    // MARK: Sign in to existing

    private var signIn: some View {
        OnboardingCard(title: "Sign in",
                       subtitle: "Your vault will be downloaded from iCloud. You need the account password and the Secret Key from your Emergency Kit.") {
            SecureField("Account Password", text: $password, prompt: Text("Account password"))
                .textContentType(.password)
            Divider()
            // Wrap (axis: .vertical) so the WHOLE key is visible — a single-line
            // field scrolls the leading "A3-…" off the left edge, hiding mistakes.
            TextField("Secret Key", text: $signInSecretKey, prompt: Text("A3-XXXXXX-XXXXXX-XXXXX-XXXXX-XXXXX-XXXXX"), axis: .vertical)
                .font(.callout.monospaced())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .lineLimit(2...4)
            Text("Your Secret Key starts with “A3-” and has 7 groups.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            errorText

            HStack {
                Button("Back") { step = .welcome }.tint(.secondary)
                Spacer()
                Button(action: performSignIn) {
                    if isWorking { ProgressView() } else { Text("Sign In").bold() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(password.isEmpty || signInSecretKey.isEmpty || isWorking)
            }
        }
    }

    private func performSignIn() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                guard let remote = try await SyncController.fetchRemoteAccount() else {
                    errorMessage = "No Passwards account was found in this iCloud account. Make sure this device is signed into the same iCloud account as your Mac."
                    isWorking = false
                    return
                }
                try await core.signInToExistingAccount(remote: remote, password: password, typedSecretKey: signInSecretKey)
            } catch AccountController.UnlockError.invalidSecretKeyFormat {
                errorMessage = "That Secret Key isn't valid. It should start with “A3-” and have 7 groups (34 letters/numbers). Check it on your Mac and re-enter it."
            } catch AccountController.UnlockError.wrongCredentials {
                errorMessage = "Couldn't unlock with that password + Secret Key. The Secret Key looks valid, so double-check the account password."
            } catch let ck as CKError {
                switch ck.code {
                case .notAuthenticated, .accountTemporarilyUnavailable:
                    errorMessage = "iCloud isn't available to Passwards. In Settings, sign into iCloud with the same Apple ID as your Mac and turn on iCloud Drive, then try again. (On the Simulator, sign in via Settings → Sign in to your iPhone.)"
                case .networkUnavailable, .networkFailure, .serviceUnavailable:
                    errorMessage = "Couldn't reach iCloud. Check your internet connection and try again."
                default:
                    errorMessage = "iCloud error: \(ck.localizedDescription)"
                }
            } catch {
                errorMessage = "Sign-in failed: \(error.localizedDescription)"
            }
            isWorking = false
        }
    }

    @ViewBuilder private var errorText: some View {
        if let errorMessage {
            Text(errorMessage).font(.callout).foregroundStyle(.red)
        }
    }
}

/// A white card on the hero gradient, holding an onboarding step's content.
private struct OnboardingCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !title.isEmpty {
                Text(title).font(.title2.bold())
            }
            if !subtitle.isEmpty {
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            content
        }
        .padding(22)
        .frame(maxWidth: 460)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .padding(.top, 40)
    }
}

/// Big white pill button for the hero (welcome) screen.
private struct HeroPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.accentDeep)
            .padding(.vertical, 14)
            .background(.white, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
