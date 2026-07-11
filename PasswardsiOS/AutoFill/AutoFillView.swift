import SwiftUI
import PasswardsCore
import PasswardsOrchestration

struct AutoFillView: View {
    let domains: [String]
    let onSelect: (String, String) -> Void
    let onCancel: () -> Void

    @State private var core: AccountController
    @State private var items: [ItemSummary] = []
    @State private var searchQuery = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private let bg = Color(red: 0.97, green: 0.96, blue: 0.99)
    private let surface = Color.white
    private let accent = Color(red: 0.36, green: 0.43, blue: 0.94) // Indigo
    private let text = Color(red: 0.19, green: 0.19, blue: 0.20)
    private let label = Color(red: 0.47, green: 0.47, blue: 0.48)
    private let danger = Color(red: 0.94, green: 0.27, blue: 0.27)

    init(domains: [String], onSelect: @escaping (String, String) -> Void, onCancel: @escaping () -> Void) {
        self.domains = domains
        self.onSelect = onSelect
        self.onCancel = onCancel
        
        let core = AccountController(
            sync: SyncController(),
            autoLock: AutoFillAutoLockService(),
            pasteboard: AutoFillPasteboardService(),
            appGroupIdentifier: "group.com.michael.passwards"
        )
        _core = State(initialValue: core)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                bg.ignoresSafeArea()
                
                switch core.phase {
                case .loading:
                    ProgressView().tint(accent)
                case .locked:
                    lockScreen
                case .unlocked:
                    unlockedScreen
                default:
                    errorScreen
                }
            }
            .navigationTitle("Passwards AutoFill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }.tint(accent)
                }
            }
        }
        .task {
            await core.boot()
            if core.phase == .locked && core.biometricUnlockAllowed {
                await unlockWithBiometrics()
            }
            if core.phase == .unlocked {
                await loadItems()
            }
        }
    }

    // MARK: - Lock Screen
    
    private var lockScreen: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundColor(accent)
                .padding(.top, 40)
            
            Text("Vault Locked").font(.title3.bold()).foregroundColor(text)
            
            VStack(spacing: 12) {
                SecureField("Master Password", text: $password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(14)
                    .background(surface)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.08), lineWidth: 1))
                
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundColor(danger)
                }
                
                Button(action: unlockWithPassword) {
                    if isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Text("Unlock").font(.body.bold()).foregroundColor(.white)
                    }
                }
                .disabled(password.isEmpty || isWorking)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(password.isEmpty || isWorking ? accent.opacity(0.5) : accent)
                .cornerRadius(12)
                
                if core.biometricUnlockAllowed {
                    Button(action: { Task { await unlockWithBiometrics() } }) {
                        HStack {
                            Image(systemName: "faceid")
                            Text("Unlock with Face ID")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(accent)
                        .padding(.top, 8)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func unlockWithPassword() {
        errorMessage = nil
        isWorking = true
        Task {
            do {
                try await core.unlock(password: password)
                await loadItems()
            } catch {
                errorMessage = "Incorrect master password."
            }
            isWorking = false
        }
    }

    private func unlockWithBiometrics() async {
        if await core.unlockWithTouchID() {
            await loadItems()
        }
    }

    // MARK: - Unlocked Screen
    
    private var unlockedScreen: some View {
        VStack(spacing: 0) {
            searchBar.padding(16)
            
            if isWorking {
                ProgressView().tint(accent).padding()
            }
            
            if filteredItems.isEmpty {
                emptyState
            } else {
                List(filteredItems) { summary in
                    Button {
                        selectCredential(for: summary)
                    } label: {
                        HStack(spacing: 12) {
                            letterAvatar(for: summary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(summary.overview.title.isEmpty ? "Untitled" : summary.overview.title)
                                    .font(.body.bold())
                                    .foregroundColor(text)
                                Text(summary.overview.subtitle).font(.footnote).foregroundColor(label)
                            }
                            Spacer()
                            Image(systemName: "key.fill").font(.caption).foregroundColor(accent)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundColor(label)
            TextField("Search credentials", text: $searchQuery)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(12)
        .background(surface)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.08), lineWidth: 1))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "questionmark.key.fill").font(.system(size: 40)).foregroundColor(label)
            Text("No logins found").font(.body.bold()).foregroundColor(text)
            Text("Try searching for a different item name.").font(.footnote).foregroundColor(label)
        }
        .padding(.top, 40)
    }

    private var errorScreen: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 40)).foregroundColor(danger)
            Text("Vault error").font(.body.bold()).foregroundColor(text)
        }
    }

    // MARK: - Helpers
    
    private var filteredItems: [ItemSummary] {
        if searchQuery.isEmpty {
            return items.filter { summary in
                guard summary.overview.category == .login else { return false }
                return domains.contains(where: { domain in
                    summary.overview.urls.contains(where: { url in
                        url.lowercased().contains(domain.lowercased())
                    })
                })
            }
        } else {
            return items.filter { summary in
                summary.overview.category == .login &&
                summary.overview.title.lowercased().contains(searchQuery.lowercased())
            }
        }
    }

    private func loadItems() async {
        guard let itemRepo = core.itemRepository else { return }
        do {
            let list = try await itemRepo.allSummaries()
            self.items = list
        } catch {}
    }

    private func selectCredential(for summary: ItemSummary) {
        errorMessage = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                guard let repo = core.itemRepository else { return }
                if let fullItem = try await repo.item(id: summary.id) {
                    let username = fullItem.details.firstField(withPurpose: .username)?.value ?? ""
                    let password = fullItem.details.firstField(withPurpose: .password)?.value ?? ""
                    onSelect(username, password)
                }
            } catch {}
        }
    }

    private func letterAvatar(for summary: ItemSummary) -> some View {
        let colors: [Color] = [.blue, .orange, .purple, .red, .green, .teal, .pink]
        let index = abs(summary.id.hashValue) % colors.count
        let char = summary.overview.title.first.map { String($0) } ?? "P"
        return Text(char.uppercased())
            .font(.body.bold())
            .foregroundColor(.white)
            .frame(width: 38, height: 38)
            .background(colors[index])
            .clipShape(Circle())
    }
}

// Dummy services for AutoFill extension lifecycle
@MainActor
struct AutoFillPasteboardService: PasteboardService {
    func copy(_ value: String, concealed: Bool) {}
    func clearSecret() {}
}

@MainActor
final class AutoFillAutoLockService: AutoLockService {
    var onShouldLock: (() -> Void)?
    func start() {}
    func stop() {}
}
