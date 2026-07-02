import SwiftUI
import PasswardsCore
import PasswardsOrchestration

/// The Security tab (Stitch "Watchtower Dashboard"): a health-score gauge, a
/// status pill, and Compromised / Reused / Weak issue cards that drill into the
/// flagged items. Powered by the shared `WatchtowerAuditor` via `IOSWatchtowerModel`.
struct IOSSecurityView: View {
    @Bindable var watchtower: IOSWatchtowerModel
    let vault: IOSVaultModel

    private struct IssueCard: Identifiable {
        let id = UUID()
        let check: WatchtowerCheck
        let count: Int
        let color: Color
        let icon: String
        let title: String
        let body: String
        let cta: String
    }

    private var issues: [IssueCard] {
        [
            IssueCard(check: .vulnerablePasswords, count: watchtower.compromised, color: Theme.danger,
                      icon: "exclamationmark.triangle.fill", title: "Compromised",
                      body: "Passwords found in known data breaches.", cta: "Review Now"),
            IssueCard(check: .reusedPasswords, count: watchtower.reused, color: Theme.warn,
                      icon: "doc.on.doc.fill", title: "Reused",
                      body: "Identical passwords across multiple accounts.", cta: "Resolve Issues"),
            IssueCard(check: .weakPasswords, count: watchtower.weak, color: Theme.link,
                      icon: "lock.open.fill", title: "Weak",
                      body: "Passwords easily guessable or too short.", cta: "Strengthen"),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    ForEach(issues) { issue in card(issue) }
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
            .background(Theme.background)
            .navigationTitle("Security")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { id in
                IOSItemDetailView(vault: vault, itemID: id, watchtower: watchtower)
            }
            .navigationDestination(for: WatchtowerCheck.self) { check in
                IOSItemList(vault: vault, source: { _ in flagged(check) }, title: check.displayName,
                            emptyText: "No items flagged.")
            }
            .refreshable { await watchtower.run() }
            .task { await watchtower.runIfStale() }
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            Text("Watchtower").font(Theme.display(28, .bold)).foregroundStyle(Theme.primaryLabel)
            Text("Your proactive security assistant. We're keeping an eye on your digital footprint.")
                .font(Theme.text(15)).foregroundStyle(Theme.label)
                .multilineTextAlignment(.center).frame(maxWidth: 300)

            ZStack {
                Circle().fill(watchtower.scoreColor.opacity(0.18)).frame(width: 160, height: 160).blur(radius: 30)
                CircularGauge(fraction: Double(watchtower.score) / 100, value: "\(watchtower.score)",
                              label: "SCORE", color: watchtower.scoreColor, size: 188, valueFont: 34,
                              labelColor: Theme.label)
            }
            .padding(.vertical, 8)

            HStack(spacing: 8) {
                Circle().fill(watchtower.scoreColor).frame(width: 10, height: 10)
                Text(watchtower.scoreStatus).font(Theme.text(13)).foregroundStyle(Theme.primaryLabel)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Theme.surfaceHigh, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.cardBorder, lineWidth: 1))
        }
    }

    private func card(_ issue: IssueCard) -> some View {
        NavigationLink(value: issue.check) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: issue.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(issue.color)
                        .frame(width: 44, height: 44)
                        .background(issue.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Spacer()
                    Text("\(issue.count)").font(Theme.display(28, .bold)).foregroundStyle(issue.color)
                }
                .padding(.bottom, 24)
                Text(issue.title).font(Theme.title(22, .bold)).foregroundStyle(Theme.primaryLabel)
                Text(issue.body).font(Theme.text(15)).foregroundStyle(Theme.label).padding(.top, 4)
                HStack(spacing: 4) {
                    Text(issue.cta).font(Theme.text(13, .semibold))
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                }
                .foregroundStyle(issue.color)
                .padding(.top, 16)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func flagged(_ check: WatchtowerCheck) -> [ItemSummary] {
        let ids = watchtower.report.items(for: check)
        return vault.summaries.filter { ids.contains($0.id) }
    }
}
