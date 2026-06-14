import SwiftUI
import TwoPasswordCore

/// The Watchtower dashboard: colored cards per non-empty check, shown in the
/// detail pane while the Watchtower sidebar entry is selected.
struct WatchtowerDashboardView: View {
    @Bindable var store: VaultStore

    private var watchtower: WatchtowerState { store.watchtower }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if watchtower.isRunning && watchtower.report.totalIssues == 0 {
                    ProgressView("Analyzing your items…")
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else if watchtower.report.totalIssues == 0 {
                    allClear
                } else {
                    cards
                }
            }
            .padding(20)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        // The window is non-opaque (frosted sidebar); keep this pane solid.
        .background(Theme.detailBackground)
        .task {
            await watchtower.runIfStale()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Watchtower")
                    .font(.title2.bold())
                Text(watchtower.report.generatedAt == .distantPast
                     ? "Checks your items for security problems."
                     : "Last checked \(watchtower.report.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await watchtower.run() }
            } label: {
                if watchtower.isRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Check Now", systemImage: "arrow.clockwise")
                }
            }
            .disabled(watchtower.isRunning)
        }
    }

    private var allClear: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("All clear")
                .font(.title3.bold())
            Text("No security issues found in your items.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var cards: some View {
        VStack(spacing: 10) {
            ForEach(WatchtowerCheck.allCases) { check in
                let count = watchtower.report.items(for: check).count
                if count > 0 {
                    Button {
                        watchtower.focus = (watchtower.focus == check) ? nil : check
                        store.selectedItemID = nil
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: symbol(for: check))
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(color(for: check).gradient, in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(check.displayName)
                                    .font(.headline)
                                Text(check.explanation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer()
                            Text("\(count)")
                                .font(.title3.bold())
                                .foregroundStyle(color(for: check))
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(
                            watchtower.focus == check ? color(for: check).opacity(0.12) : Color.secondary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func color(for check: WatchtowerCheck) -> Color {
        switch check.severity {
        case 0: Color(.sRGB, red: 0.88, green: 0.25, blue: 0.25)
        case 1: Color(.sRGB, red: 0.95, green: 0.52, blue: 0.11)
        case 2: Color(.sRGB, red: 0.85, green: 0.65, blue: 0.05)
        default: Theme.accent
        }
    }

    private func symbol(for check: WatchtowerCheck) -> String {
        switch check {
        case .vulnerablePasswords: "exclamationmark.shield.fill"
        case .reusedPasswords: "repeat"
        case .weakPasswords: "wand.and.rays.inverse"
        case .unsecuredWebsites: "lock.open.fill"
        case .twoFactorAvailable: "key.radiowaves.forward.fill"
        case .expiringItems: "calendar.badge.exclamationmark"
        case .duplicateItems: "doc.on.doc.fill"
        }
    }
}

/// Colored alert banner at the top of a flagged item's detail view.
struct WatchtowerBanner: View {
    let check: WatchtowerCheck
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            VStack(alignment: .leading, spacing: 1) {
                Text(check.displayName)
                    .font(.callout.weight(.semibold))
                Text(check.explanation)
                    .font(.caption)
                    .opacity(0.85)
            }
            Spacer()
            Button("Dismiss") { onDismiss() }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .opacity(0.8)
                .help("Don't flag this item for this check again")
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(bannerColor.gradient, in: RoundedRectangle(cornerRadius: 8))
    }

    private var bannerColor: Color {
        switch check.severity {
        case 0: Color(.sRGB, red: 0.85, green: 0.22, blue: 0.22)
        case 1: Color(.sRGB, red: 0.92, green: 0.48, blue: 0.10)
        case 2: Color(.sRGB, red: 0.80, green: 0.62, blue: 0.05)
        default: Theme.accentDeep
        }
    }
}
