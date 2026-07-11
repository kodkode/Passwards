import SwiftUI
import UIKit
import PasswardsCore
import PasswardsOrchestration
import UniformTypeIdentifiers

// MARK: - Add sheet (choose a type → editor)

/// Bottom sheet: search + a 2-column grid of glossy type tiles. Picking a type
/// pushes the editor for a fresh item; saving creates it and dismisses the sheet.
struct IOSAddSheet: View {
    let vault: IOSVaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    private var categories: [PasswardsCore.Category] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return PasswardsCore.Category.allCases.filter { q.isEmpty || $0.displayName.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Card(padding: 14) {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass").foregroundStyle(Theme.label)
                            TextField("What do you want to save?", text: $query)
                                .font(Theme.text(15.5)).autocorrectionDisabled().textInputAutocapitalization(.never)
                        }
                    }
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(categories, id: \.self) { category in
                            NavigationLink(value: category) { typeTile(category) }
                                .buttonStyle(PressScale())
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark").fontWeight(.semibold) }.tint(Theme.label)
                }
            }
            .navigationDestination(for: PasswardsCore.Category.self) { category in
                IOSItemEditorView(vault: vault, original: vault.newItem(category: category),
                                  isNew: true, showsCancel: false, onClose: { dismiss() })
            }
        }
        .presentationCornerRadius(Theme.rSheet)
    }

    private func typeTile(_ category: PasswardsCore.Category) -> some View {
        VStack(spacing: 10) {
            CategoryIcon(category: category, size: 48)
            Text(category.displayName).font(Theme.text(13.5, .semibold)).foregroundStyle(Theme.primaryLabel)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.rBadge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.rBadge, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
    }
}

// MARK: - Settings sheet

struct IOSSettingsSheet: View {
    let vault: IOSVaultModel
    private var core: AccountController { vault.core }
    @Environment(\.dismiss) private var dismiss

    @State private var faceIDOn = BiometricUnlock.isEnrolled
    @State private var faceIDError: String?
    @AppStorage(IOSAppearance.storageKey) private var appearanceRaw = IOSAppearance.system.rawValue
    @AppStorage(SettingsKeys.lockWhenBackgroundMinutes) private var autoLockMinutes = 0

    // Backup & Restore
    @State private var exportingBackup = false
    @State private var backupData: BackupDocument?
    @State private var importingBackup = false
    @State private var restoreData: Data?
    @State private var restoreHeader: BackupFile?
    @State private var backupError: String?

    // Emergency Kit
    @State private var showingKitSheet = false
    @State private var kitPassword = ""
    @State private var isVerifyingKit = false
    @State private var kitError: String?
    @State private var verifiedKey: SecretKey?

    private let autoLockOptions = [0, 1, 5, 15]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    profileCard
                    
                    SectionHeader(title: "Preferences")
                    appearanceCard
                    
                    SectionHeader(title: "iCloud Sync")
                    syncCard(sync: Bindable(core.sync))
                    
                    SectionHeader(title: "Security")
                    securityCard
                    
                    SectionHeader(title: "Backup & Recovery")
                    backupCard
                    emergencyKitCard
                    
                    Button { core.lock(); dismiss() } label: {
                        Text("Lock Now").font(Theme.text(16, .semibold)).foregroundStyle(Theme.accentText)
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.rInput, style: .continuous))
                    }
                    .buttonStyle(PressScale())
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.tint(Theme.accent) }
            }
            .fileExporter(isPresented: $exportingBackup, document: backupData, contentType: .data, defaultFilename: "Passwards Backup.pwbackup") { result in
                switch result {
                case .success:
                    backupError = nil
                case .failure(let error):
                    backupError = "Failed to export backup: \(error.localizedDescription)"
                }
            }
            .fileImporter(isPresented: $importingBackup, allowedContentTypes: [.data]) { result in
                switch result {
                case .success(let url):
                    guard url.startAccessingSecurityScopedResource() else {
                        backupError = "Access denied to backup file."
                        return
                    }
                    defer { url.stopAccessingSecurityScopedResource() }
                    do {
                        let data = try Data(contentsOf: url)
                        let file = try BackupArchive.decode(data)
                        self.restoreData = data
                        self.restoreHeader = file
                    } catch {
                        backupError = "Invalid backup file: \(error.localizedDescription)"
                    }
                case .failure(let error):
                    backupError = "Failed to import backup: \(error.localizedDescription)"
                }
            }
            .sheet(item: Binding(
                get: { restoreHeader.map { IdentifiedBackup(header: $0, data: restoreData ?? Data()) } },
                set: { val in
                    if val == nil {
                        restoreHeader = nil
                        restoreData = nil
                    }
                }
            )) { identified in
                IOSRestoreBackupSheet(core: core, fileData: identified.data, header: identified.header)
            }
            .sheet(isPresented: $showingKitSheet) {
                emergencyKitSheet
            }
        }
        .presentationCornerRadius(Theme.rSheet)
    }

    private var profileCard: some View {
        Card {
            HStack(spacing: 14) {
                Avatar(initials: accountInitials(core), size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(core.account?.email ?? "Your Account").font(Theme.title(17, .semibold))
                        .foregroundStyle(Theme.primaryLabel).lineLimit(1)
                    Text("Passwards account").font(Theme.text(13)).foregroundStyle(Theme.label)
                }
                Spacer()
            }
        }
    }

    private var appearanceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("APPEARANCE").font(Theme.caps(12, .bold)).tracking(0.5).foregroundStyle(Theme.label)
                Picker("", selection: $appearanceRaw) {
                    ForEach(IOSAppearance.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private func syncCard(sync: Bindable<SyncController>) -> some View {
        Card {
            VStack(spacing: 4) {
                Toggle(isOn: sync.syncEnabled) {
                    settingLabel("Sync with iCloud", icon: "cloud.fill", tint: Theme.accent)
                }
                .tint(Theme.accent)
                
                Divider().overlay(Theme.cardBorder).padding(.vertical, 4)
                
                HStack {
                    settingLabel("Sync Status", icon: "arrow.triangle.2.circlepath", tint: Theme.accent)
                    Spacer()
                    Text(syncStatusText).font(Theme.text(15)).foregroundStyle(syncStatusColor)
                }
            }
        }
    }

    private var syncStatusText: String {
        switch core.sync.status {
        case .disabled: return "Off"
        case .idle: return "Up to date"
        case .syncing: return "Syncing…"
        case .error(let message): return message
        case .accountUnavailable: return "iCloud unavailable"
        }
    }

    private var syncStatusColor: Color {
        switch core.sync.status {
        case .idle: return Theme.label
        case .syncing: return Theme.accent
        case .error, .accountUnavailable: return Theme.danger
        case .disabled: return Theme.label
        }
    }

    private var securityCard: some View {
        Card {
            VStack(spacing: 4) {
                if BiometricUnlock.isAvailable {
                    Toggle(isOn: $faceIDOn) {
                        settingLabel("Unlock with Face ID", icon: "faceid", tint: Theme.accent)
                    }
                    .tint(Theme.accent)
                    .onChange(of: faceIDOn) { _, on in setFaceID(on) }
                    Divider().overlay(Theme.cardBorder).padding(.vertical, 4)
                }
                Button { cycleAutoLock() } label: {
                    HStack {
                        settingLabel("Auto-Lock", icon: "lock.rotation", tint: Theme.color(token: "purple"))
                        Spacer()
                        Text(autoLockLabel).font(Theme.text(15)).foregroundStyle(Theme.label)
                    }
                }
                .buttonStyle(.plain)
                if let faceIDError {
                    Text(faceIDError).font(Theme.text(12.5)).foregroundStyle(Theme.danger).padding(.top, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var backupCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    Task {
                        do {
                            let data = try await core.makeBackupData(includeRecovery: true)
                            self.backupData = BackupDocument(data: data)
                            self.exportingBackup = true
                        } catch {
                            backupError = "Backup failed: \(error.localizedDescription)"
                        }
                    }
                } label: {
                    HStack {
                        settingLabel("Save Encrypted Backup…", icon: "square.and.arrow.up", tint: Theme.color(token: "teal"))
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                
                Divider().overlay(Theme.cardBorder)
                
                Button {
                    importingBackup = true
                } label: {
                    HStack {
                        settingLabel("Restore from Backup…", icon: "square.and.arrow.down", tint: Theme.color(token: "orange"))
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                
                if let backupError {
                    Text(backupError).font(Theme.text(12.5)).foregroundStyle(Theme.danger).padding(.top, 4)
                }
            }
        }
    }

    private var emergencyKitCard: some View {
        Card {
            Button {
                showingKitSheet = true
            } label: {
                HStack {
                    settingLabel("Emergency Kit…", icon: "doc.richtext", tint: Theme.color(token: "purple"))
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var emergencyKitSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let key = verifiedKey {
                        Card {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("This is your Secret Key. Store the kit somewhere safe — you'll need it to set up a new device.")
                                    .font(Theme.text(14)).foregroundStyle(Theme.label)
                                
                                Text(key.formatted).font(Theme.mono(15, .semibold)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                    .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: Theme.rInput))
                                
                                HStack(spacing: 16) {
                                    Button { UIPasteboard.general.string = key.formatted } label: {
                                        Label("Copy Key", systemImage: "doc.on.doc")
                                    }
                                    if let email = core.account?.email {
                                        let pdfData = IOSEmergencyKitPDF.render(email: email, secretKey: key)
                                        ShareLink(item: pdfData, preview: SharePreview("Passwards Emergency Kit.pdf", icon: Image(systemName: "doc.richtext"))) {
                                            Label("Share PDF Kit", systemImage: "square.and.arrow.up")
                                        }
                                    }
                                }
                                .font(Theme.text(14, .semibold)).tint(Theme.accent)
                            }
                        }
                    } else {
                        Card {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Verify it's you to reveal your Secret Key and export the Emergency Kit.").font(Theme.text(14)).foregroundStyle(Theme.label)
                                
                                SecureField("Account Password", text: $kitPassword)
                                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                                    .padding(12)
                                    .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: Theme.rInput))
                                
                                if let kitError {
                                    Text(kitError).font(Theme.text(13)).foregroundStyle(Theme.danger)
                                }
                                
                                Button(action: verifyKitPassword) {
                                    if isVerifyingKit {
                                        ProgressView().tint(.white)
                                    } else {
                                        Text("Verify").font(Theme.text(16, .bold)).foregroundStyle(Theme.accentText)
                                    }
                                }
                                .disabled(kitPassword.isEmpty || isVerifyingKit)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(kitPassword.isEmpty || isVerifyingKit ? Theme.accent.opacity(0.5) : Theme.accent, in: RoundedRectangle(cornerRadius: Theme.rInput))
                                .buttonStyle(PressScale())
                            }
                        }
                        .task {
                            if core.biometricUnlockAllowed {
                                await verifyKitWithBiometrics()
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Emergency Kit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        showingKitSheet = false
                        kitPassword = ""
                        kitError = nil
                        verifiedKey = nil
                    }
                    .tint(Theme.label)
                }
            }
        }
        .presentationCornerRadius(Theme.rSheet)
    }

    private func verifyKitPassword() {
        guard let account = core.account else { return }
        kitError = nil
        isVerifyingKit = true
        Task {
            if await core.verifyAccountPassword(kitPassword) {
                if let key = KeychainStore.loadSecretKey(accountID: account.id) {
                    self.verifiedKey = key
                } else {
                    kitError = "The Secret Key isn't stored on this device."
                }
            } else {
                kitError = "The account password is incorrect."
            }
            isVerifyingKit = false
        }
    }

    private func verifyKitWithBiometrics() async {
        guard let account = core.account else { return }
        let result = await BiometricUnlock.unlock(reason: "reveal your Secret Key")
        if case .success = result {
            if let key = KeychainStore.loadSecretKey(accountID: account.id) {
                self.verifiedKey = key
            } else {
                kitError = "The Secret Key isn't stored on this device."
            }
        }
    }

    private func settingLabel(_ text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            GlossyIcon(symbol: icon, color: tint, size: 30)
            Text(text).font(Theme.text(16)).foregroundStyle(Theme.primaryLabel)
        }
    }

    private var autoLockLabel: String { autoLockMinutes == 0 ? "Immediately" : "\(autoLockMinutes) min" }

    private func cycleAutoLock() {
        let idx = autoLockOptions.firstIndex(of: autoLockMinutes) ?? 0
        autoLockMinutes = autoLockOptions[(idx + 1) % autoLockOptions.count]
    }

    private func setFaceID(_ on: Bool) {
        faceIDError = nil
        Task {
            if on {
                guard let masterKey = await core.keyStore.masterKey else {
                    faceIDOn = false; faceIDError = "Unlock first, then enable Face ID."; return
                }
                do { try BiometricUnlock.enroll(masterKey: masterKey) }
                catch { faceIDOn = false; faceIDError = "Couldn't enable Face ID: \(error.localizedDescription)" }
            } else {
                BiometricUnlock.disable()
            }
        }
    }
}

// MARK: - Collection sheet (a list of items for a category / vault / flagged check)

struct IOSCollectionSheet: View {
    let vault: IOSVaultModel
    let kind: CollectionKind
    var watchtower: IOSWatchtowerModel?
    @Environment(\.dismiss) private var dismiss

    private var items: [ItemSummary] {
        switch kind {
        case .all: return vault.activeSummaries
        case .favorites: return vault.activeSummaries.filter { $0.overview.isFavorite }
        case .recent: return Array(vault.activeSummaries.sorted { $0.createdAt > $1.createdAt }.prefix(20))
        case .archive: return vault.archivedSummaries
        case .trash: return vault.trashedSummaries
        case .category(let c): return vault.items(in: c)
        case .tag(let t): return vault.items(taggedWith: t)
        case .vault(let name): return itemsInVault(name)
        case .flagged(let check):
            let ids = watchtower?.report.items(for: check) ?? []
            return vault.summaries.filter { ids.contains($0.id) }
        }
    }

    private func itemsInVault(_ name: String) -> [ItemSummary] {
        guard let v = vault.vaults.first(where: { $0.attributes.name == name }) else { return vault.activeSummaries }
        return vault.activeSummaries.filter { $0.vaultID == v.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if items.isEmpty {
                        emptyState.padding(.top, 40)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { idx, s in
                                NavigationLink(value: s.id) {
                                    ItemRowContent(vault: vault, summary: s)
                                }
                                .buttonStyle(PressScale(scale: 0.98))
                                if idx < items.count - 1 { Divider().overlay(Theme.cardBorder).padding(.leading, 68) }
                            }
                        }
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
                        .padding(20)
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark").fontWeight(.semibold) }.tint(Theme.label)
                }
            }
            .navigationDestination(for: String.self) { id in
                IOSItemDetailView(vault: vault, itemID: id, watchtower: watchtower)
            }
        }
        .presentationCornerRadius(Theme.rSheet)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            GlossyIcon(symbol: "tray", color: Theme.color(token: "slate"), size: 52)
            Text("Nothing here yet").font(Theme.title(18, .semibold)).foregroundStyle(Theme.primaryLabel)
            Text("Items you save to \(kind.title) will show up here.")
                .font(Theme.text(14)).foregroundStyle(Theme.label).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 40)
    }
}

/// Row content used inside NavigationLink (no button wrapper).
struct ItemRowContent: View {
    let vault: IOSVaultModel
    let summary: ItemSummary
    var body: some View {
        HStack(spacing: 12) {
            ItemIcon(overview: summary.overview, favicon: vault.favicon(for: summary.overview), size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.overview.title.isEmpty ? "Untitled" : summary.overview.title)
                    .font(Theme.text(15, .semibold)).foregroundStyle(Theme.primaryLabel).lineLimit(1)
                if !summary.overview.subtitle.isEmpty {
                    Text(summary.overview.subtitle).font(Theme.text(12.5)).foregroundStyle(Theme.label).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if summary.overview.isFavorite {
                Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(Theme.warn)
            }
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.label)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Vault sheet (members are a deferred-sharing placeholder)

struct IOSVaultSheet: View {
    let vault: IOSVaultModel
    let vaultName: String
    @Environment(\.dismiss) private var dismiss

    private var items: [ItemSummary] {
        guard let v = vault.vaults.first(where: { $0.attributes.name == vaultName }) else { return vault.activeSummaries }
        return vault.activeSummaries.filter { $0.vaultID == v.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 10) {
                        GlossyIcon(symbol: "lock.fill", color: Theme.color(token: "slate"), size: 64)
                        Text(vaultName).font(Theme.title(22, .semibold)).foregroundStyle(Theme.primaryLabel)
                        Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                            .font(Theme.text(14)).foregroundStyle(Theme.label)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 8)

                    membersSection
                    itemsSection
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark").fontWeight(.semibold) }.tint(Theme.label)
                }
            }
            .navigationDestination(for: String.self) { id in
                IOSItemDetailView(vault: vault, itemID: id)
            }
        }
        .presentationCornerRadius(Theme.rSheet)
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Members")
            Card {
                HStack(spacing: 12) {
                    Avatar(initials: accountInitials(vault.core), size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vault.core.account?.email ?? "You").font(Theme.text(15, .semibold))
                            .foregroundStyle(Theme.primaryLabel).lineLimit(1)
                        Text("Owner").font(Theme.text(13)).foregroundStyle(Theme.accent)
                    }
                    Spacer()
                }
            }
            Text("Sharing a vault with other people is coming soon.")
                .font(Theme.text(12.5)).foregroundStyle(Theme.label)
        }
    }

    @ViewBuilder private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Items")
            if items.isEmpty {
                Text("No items in this vault yet.").font(Theme.text(14)).foregroundStyle(Theme.label)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, s in
                        NavigationLink(value: s.id) { ItemRowContent(vault: vault, summary: s) }
                            .buttonStyle(PressScale(scale: 0.98))
                        if idx < items.count - 1 { Divider().overlay(Theme.cardBorder).padding(.leading, 68) }
                    }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
            }
        }
    }
}

// MARK: - Backup and Recovery helper views & sheets

struct IdentifiedBackup: Identifiable {
    let id = UUID()
    let header: BackupFile
    let data: Data
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data
    
    init(data: Data) {
        self.data = data
    }
    
    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct IOSRestoreBackupSheet: View {
    let core: AccountController
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
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Backup from \(header.account.email)").font(Theme.title(16, .semibold)).foregroundStyle(Theme.primaryLabel)
                            Text("Created \(header.createdAt.formatted(date: .abbreviated, time: .shortened))").font(Theme.text(13)).foregroundStyle(Theme.label)
                        }
                    }
                    
                    if core.account != nil {
                        Card {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
                                Text("This replaces everything in your current vault.").font(Theme.text(14, .medium)).foregroundStyle(Theme.danger)
                            }
                        }
                    }
                    
                    Card {
                        VStack(spacing: 12) {
                            if useRecoveryCode {
                                secureField("Recovery Code", text: $recoveryCode, prompt: "RC-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX")
                                    .font(Theme.mono(14))
                                secureField("New Password", text: $newPassword, prompt: "New password (10+ characters)", isSecure: true)
                                if !newPassword.isEmpty {
                                    StrengthBar(score: newScore)
                                }
                                secureField("Confirm New Password", text: $confirmPassword, prompt: "Confirm new password", isSecure: true)
                            } else {
                                secureField("Account Password", text: $password, prompt: "Account password", isSecure: true)
                                secureField("Secret Key", text: $secretKey, prompt: "A3-XXXXXX-XXXXXX-XXXXX-XXXXX-XXXXX-XXXXX")
                                    .font(Theme.mono(14))
                            }
                            
                            Button(useRecoveryCode ? "Use account password & Secret Key instead" : "Use a recovery code instead") {
                                useRecoveryCode.toggle()
                                errorMessage = nil
                            }
                            .font(Theme.text(14, .medium)).foregroundStyle(Theme.accent)
                            .padding(.top, 4)
                        }
                    }
                    
                    if let errorMessage {
                        Text(errorMessage).font(Theme.text(13.5)).foregroundStyle(Theme.danger).multilineTextAlignment(.center)
                    }
                    
                    Button(action: restore) {
                        if isWorking {
                            ProgressView().tint(.white)
                        } else {
                            Text("Restore Backup").font(Theme.text(16, .bold)).foregroundStyle(Theme.accentText)
                        }
                    }
                    .disabled(!formValid || isWorking)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(formValid && !isWorking ? Theme.accent : Theme.accent.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.rInput))
                    .buttonStyle(PressScale())
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Restore Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(Theme.label)
                }
            }
        }
        .presentationCornerRadius(Theme.rSheet)
    }

    private func secureField(_ label: String, text: Binding<String>, prompt: String, isSecure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.caps(11, .bold)).foregroundStyle(Theme.label)
            Group {
                if isSecure {
                    SecureField(prompt, text: text)
                } else {
                    TextField(prompt, text: text)
                }
            }
            .autocorrectionDisabled().textInputAutocapitalization(.never)
            .padding(12)
            .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: Theme.rInput))
        }
    }

    private func restore() {
        errorMessage = nil
        if useRecoveryCode, newScore < .fair {
            errorMessage = "That password is too weak. Make it longer or add symbols."
            return
        }
        isWorking = true
        Task {
            do {
                if useRecoveryCode {
                    try await core.restoreBackup(fileData: fileData, recoveryCode: recoveryCode, newPassword: newPassword)
                } else {
                    try await core.restoreBackup(fileData: fileData, password: password, typedSecretKey: secretKey)
                }
                dismiss()
            } catch AccountController.BackupRestoreError.wrongCredentials {
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

// MARK: - Emergency Kit PDF Exporter

enum IOSEmergencyKitPDF {
    static func render(email: String, secretKey: SecretKey, recoveryCode: String? = nil) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return pdfRenderer.pdfData { context in
            context.beginPage()
            let cgContext = context.cgContext
            
            // Header band in brand blue
            let headerRect = CGRect(x: 0, y: 0, width: 612, height: 80)
            UIColor(red: 0x05 / 255, green: 0x72 / 255, blue: 0xEC / 255, alpha: 1).setFill()
            cgContext.fill(headerRect)
            
            func draw(_ string: String, at point: CGPoint, font: UIFont, color: UIColor = .black) {
                (string as NSString).draw(
                    at: point,
                    withAttributes: [.font: font, .foregroundColor: color]
                )
            }
            
            draw("Passwards Emergency Kit", at: CGPoint(x: 48, y: 26), font: UIFont.boldSystemFont(ofSize: 24), color: .white)
            draw("Keep this document somewhere safe — anyone with it and your account password can access your data.",
                 at: CGPoint(x: 48, y: 90), font: UIFont.systemFont(ofSize: 10), color: .darkGray)
            
            var y: CGFloat = 140
            func field(_ label: String, _ value: String, monospaced: Bool = false) {
                draw(label.uppercased(), at: CGPoint(x: 48, y: y), font: UIFont.boldSystemFont(ofSize: 9), color: .gray)
                let font = monospaced
                    ? UIFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
                    : UIFont.systemFont(ofSize: 14)
                draw(value, at: CGPoint(x: 48, y: y + 16), font: font)
                y += 64
            }
            
            field("Created", Date().formatted(date: .long, time: .shortened))
            field("Email address", email)
            field("Secret Key", secretKey.formatted, monospaced: true)
            if let recoveryCode {
                field("Recovery Code", recoveryCode, monospaced: true)
            }
            
            draw("ACCOUNT PASSWORD", at: CGPoint(x: 48, y: y), font: UIFont.boldSystemFont(ofSize: 9), color: .gray)
            UIColor.gray.setStroke()
            cgContext.setLineWidth(0.5)
            cgContext.move(to: CGPoint(x: 48, y: y + 24))
            cgContext.addLine(to: CGPoint(x: 400, y: y + 24))
            cgContext.strokePath()
            draw("Write your account password here, or leave blank and memorize it.",
                 at: CGPoint(x: 48, y: y + 36), font: UIFont.systemFont(ofSize: 9), color: .gray)
            
            draw("Your Secret Key is stored only on this iPhone's Keychain and in this document. " +
                 "Without it, your data cannot be decrypted on a new device.",
                 at: CGPoint(x: 48, y: 700), font: UIFont.systemFont(ofSize: 9), color: .darkGray)
        }
    }
}
