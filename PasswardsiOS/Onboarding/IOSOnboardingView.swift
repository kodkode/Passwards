import SwiftUI
import UIKit
import CloudKit
import PasswardsCore
import PasswardsOrchestration

/// iOS account setup (playful): a 3-slide intro, then email + password → Secret Key
/// → Face ID, plus a "sign in to an existing account" path that pulls the account
/// from iCloud. Light lavender background, glossy icons, rounded cards.
struct IOSOnboardingView: View {
    let core: AccountController

    enum Step { case welcome, credentials, secretKey, faceID, signIn }

    @State private var step: Step

    init(core: AccountController, initialStep: Step = .welcome) {
        self.core = core
        _step = State(initialValue: initialStep)
    }
    @State private var slide = 0
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
            Theme.background.ignoresSafeArea()
            switch step {
            case .welcome: intro
            case .credentials: formScreen { credentials }
            case .secretKey: formScreen { secretKeyStep }
            case .faceID: formScreen { faceIDStep }
            case .signIn: formScreen { signIn }
            }
        }
    }

    // MARK: Intro slides

    private struct Slide { let usesAppMark: Bool; let icon: String; let color: Color; let title: String; let body: String }
    private let slides: [Slide] = [
        .init(usesAppMark: true, icon: "shield.fill", color: Theme.accent,
              title: "Your secrets, locked down", body: "Passwords, cards, notes — all sealed up tight and just for you."),
        .init(usesAppMark: false, icon: "lock.rectangle.stack.fill", color: Theme.color(token: "teal"),
              title: "Passwords, but make them strong", body: "One tap and boom — a password no one is guessing. Ever."),
        .init(usesAppMark: false, icon: "key.fill", color: Theme.color(token: "purple"),
              title: "Breeze through sign-ins", body: "Autofill swoops in so you can skip the typing and get on with it."),
    ]

    private var intro: some View {
        VStack {
            HStack {
                Spacer()
                Button("Skip") { step = .credentials }.font(Theme.text(15, .medium)).foregroundStyle(Theme.label)
            }
            .padding(.horizontal, 24).padding(.top, 8)

            TabView(selection: $slide) {
                ForEach(Array(slides.enumerated()), id: \.offset) { idx, s in
                    VStack(spacing: 22) {
                        Spacer()
                        if s.usesAppMark { AppMark(size: 104) }
                        else { GlossyIcon(symbol: s.icon, color: s.color, size: 104) }
                        Text(s.title).font(Theme.display(28, .semibold)).tracking(-0.3)
                            .foregroundStyle(Theme.primaryLabel).multilineTextAlignment(.center)
                        Text(s.body).font(Theme.text(15)).foregroundStyle(Theme.label)
                            .multilineTextAlignment(.center).lineSpacing(3).padding(.horizontal, 20)
                        Spacer(); Spacer()
                    }
                    .padding(.horizontal, 20)
                    .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            dots.padding(.bottom, 24)

            VStack(spacing: 12) {
                Button {
                    if slide < slides.count - 1 { withAnimation { slide += 1 } } else { step = .credentials }
                } label: {
                    Text(slide < slides.count - 1 ? "Next" : "Get Started")
                        .font(Theme.text(16, .bold)).frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryPill())

                if SyncController.hasCloudKitEntitlement {
                    Button("Sign in to an existing account") { step = .signIn }
                        .font(Theme.text(15, .medium)).foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<slides.count, id: \.self) { i in
                Capsule().fill(i == slide ? Theme.accent : Theme.label.opacity(0.4))
                    .frame(width: i == slide ? 20 : 6, height: 6)
            }
        }
    }

    // MARK: Form scaffold

    private func formScreen<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        ScrollView {
            content().padding(20).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Create account

    private var credentials: some View {
        OnboardingCard(title: "Create your account",
                       subtitle: "Your account password protects everything. Make it long and memorable — it can never be recovered if forgotten.") {
            field { TextField("Email", text: $email, prompt: Text("you@example.com"))
                .textContentType(.username).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled() }
            field { SecureField("Account Password", text: $password, prompt: Text("Account password"))
                .textContentType(.newPassword) }
            if !password.isEmpty { StrengthBar(score: passwordScore) }
            field { SecureField("Confirm Password", text: $confirmPassword, prompt: Text("Confirm password"))
                .textContentType(.newPassword) }
            errorText
            HStack {
                Button("Back") { step = .welcome }.foregroundStyle(Theme.label)
                Spacer()
                Button(action: create) {
                    if isWorking { ProgressView().tint(Theme.accentText) } else { Text("Continue").font(Theme.text(16, .bold)) }
                }
                .buttonStyle(PrimaryPill()).disabled(!createValid || isWorking)
            }
        }
    }

    private func create() {
        errorMessage = nil
        guard passwordScore >= .fair else {
            errorMessage = "That password is too weak to protect a vault. Add more words or characters."; return
        }
        isWorking = true
        Task {
            do { result = try await core.createAccount(email: email, password: password); step = .secretKey }
            catch { errorMessage = "Account creation failed: \(error.localizedDescription)" }
            isWorking = false
        }
    }

    // MARK: Secret Key

    private var secretKeyStep: some View {
        OnboardingCard(title: "Your Secret Key",
                       subtitle: "This key encrypts your data together with your password. It's kept in this iPhone's Keychain — save it somewhere safe in case you set up a new device.") {
            if let result {
                Text(result.secretKey.formatted).font(Theme.mono(15, .semibold)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: Theme.rInput))
                HStack(spacing: 12) {
                    Button { UIPasteboard.general.string = result.secretKey.formatted } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    ShareLink(item: result.secretKey.formatted) { Label("Share", systemImage: "square.and.arrow.up") }
                }
                .font(Theme.text(14, .medium)).tint(Theme.accent)
            }
            Toggle("I've saved my Secret Key somewhere safe", isOn: $savedKitConfirmed)
                .tint(Theme.accent).font(Theme.text(14))
            HStack {
                Spacer()
                Button("Continue") {
                    if BiometricUnlock.isAvailable { step = .faceID } else { core.finishOnboarding() }
                }
                .font(Theme.text(16, .bold)).buttonStyle(PrimaryPill()).disabled(!savedKitConfirmed)
            }
        }
    }

    // MARK: Face ID

    private var faceIDStep: some View {
        OnboardingCard(title: "", subtitle: "") {
            VStack(spacing: 14) {
                GlossyIcon(symbol: "faceid", color: Theme.accent, size: 64)
                Text("Unlock with Face ID").font(Theme.title(20, .semibold)).foregroundStyle(Theme.primaryLabel)
                Text("Use Face ID to unlock Passwards quickly. Your account password is still required from time to time.")
                    .font(Theme.text(14)).foregroundStyle(Theme.label).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            HStack {
                Button("Not Now") { core.finishOnboarding() }.foregroundStyle(Theme.label)
                Spacer()
                Button("Enable Face ID") {
                    Task {
                        if let masterKey = await core.keyStore.masterKey { try? BiometricUnlock.enroll(masterKey: masterKey) }
                        core.finishOnboarding()
                    }
                }
                .font(Theme.text(16, .bold)).buttonStyle(PrimaryPill())
            }
        }
    }

    // MARK: Sign in

    private var signIn: some View {
        OnboardingCard(title: "Sign in",
                       subtitle: "Your vault will be downloaded from iCloud. You need the account password and the Secret Key from your Emergency Kit.") {
            field { SecureField("Account Password", text: $password, prompt: Text("Account password"))
                .textContentType(.password) }
            field {
                TextField("Secret Key", text: $signInSecretKey,
                          prompt: Text("A3-XXXXXX-XXXXXX-XXXXX-XXXXX-XXXXX-XXXXX"), axis: .vertical)
                    .font(Theme.mono(14)).textInputAutocapitalization(.characters).autocorrectionDisabled().lineLimit(2...4)
            }
            Text("Your Secret Key starts with “A3-” and has 7 groups.")
                .font(Theme.text(12)).foregroundStyle(Theme.label)
            errorText
            HStack {
                Button("Back") { step = .welcome }.foregroundStyle(Theme.label)
                Spacer()
                Button(action: performSignIn) {
                    if isWorking { ProgressView().tint(Theme.accentText) } else { Text("Sign In").font(Theme.text(16, .bold)) }
                }
                .buttonStyle(PrimaryPill()).disabled(password.isEmpty || signInSecretKey.isEmpty || isWorking)
            }
        }
    }

    private func performSignIn() {
        isWorking = true; errorMessage = nil
        Task {
            do {
                guard let remote = try await SyncController.fetchRemoteAccount() else {
                    errorMessage = "No Passwards account was found in this iCloud account. Make sure this device is signed into the same iCloud account as your Mac."
                    isWorking = false; return
                }
                try await core.signInToExistingAccount(remote: remote, password: password, typedSecretKey: signInSecretKey)
            } catch AccountController.UnlockError.invalidSecretKeyFormat {
                errorMessage = "That Secret Key isn't valid. It should start with “A3-” and have 7 groups (34 letters/numbers). Check it on your Mac and re-enter it."
            } catch AccountController.UnlockError.wrongCredentials {
                errorMessage = "Couldn't unlock with that password + Secret Key. The Secret Key looks valid, so double-check the account password."
            } catch let ck as CKError {
                switch ck.code {
                case .notAuthenticated, .accountTemporarilyUnavailable:
                    errorMessage = "iCloud isn't available to Passwards. In Settings, sign into iCloud with the same Apple ID as your Mac and turn on iCloud Drive, then try again."
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

    // MARK: Helpers

    private func field<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .font(Theme.text(16)).padding(.horizontal, 14).padding(.vertical, 12)
            .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: Theme.rInput, style: .continuous))
    }

    @ViewBuilder private var errorText: some View {
        if let errorMessage {
            Text(errorMessage).font(Theme.text(14)).foregroundStyle(Theme.danger)
        }
    }
}

/// A surface card holding an onboarding step's content.
private struct OnboardingCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !title.isEmpty { Text(title).font(Theme.title(24, .semibold)).foregroundStyle(Theme.primaryLabel) }
            if !subtitle.isEmpty { Text(subtitle).font(Theme.text(14.5)).foregroundStyle(Theme.label) }
            content
        }
        .padding(22)
        .frame(maxWidth: 460)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        .padding(.top, 40)
    }
}

/// Full-width accent pill button.
struct PrimaryPill: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.accentText)
            .padding(.vertical, 15).padding(.horizontal, 22)
            .background(Theme.accent, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
