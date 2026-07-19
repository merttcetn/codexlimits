import SwiftUI
import WidgetKit

#if !DESIGN_PREVIEW
@main
struct CodexLimitsWidgetBundle: WidgetBundle {
    var body: some Widget {
        CodexLimitsWidget()
    }
}
#endif

struct CodexLimitsWidget: Widget {
    let kind = "CodexLimitsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LimitTimelineProvider()) { entry in
            CodexLimitsWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    CodexAuroraBackground()
                }
        }
        .configurationDisplayName("Codex Limits")
        .description("See Codex limits and reset-credit expirations across your configured accounts.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct LimitEntry: TimelineEntry {
    let date: Date
    let dashboard: CodexDashboardSnapshot?
}

struct LimitTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> LimitEntry {
        LimitEntry(date: .now, dashboard: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (LimitEntry) -> Void) {
        completion(LimitEntry(date: .now, dashboard: context.isPreview ? .preview : SnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LimitEntry>) -> Void) {
        let entry = LimitEntry(date: .now, dashboard: SnapshotStore.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct CodexLimitsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LimitEntry
    var previewFamily: WidgetFamily?

    init(entry: LimitEntry, previewFamily: WidgetFamily? = nil) {
        self.entry = entry
        self.previewFamily = previewFamily
    }

    var body: some View {
        Group {
            if let dashboard = entry.dashboard,
               let firstAccount = dashboard.firstAvailableAccount {
                switch previewFamily ?? family {
                case .systemLarge:
                    MultiAccountLargeView(dashboard: dashboard)
                case .systemMedium where dashboard.accountsForWidget(limit: 2).filter({ $0.limits != nil }).count > 1:
                    MultiAccountMediumView(dashboard: dashboard)
                case .systemMedium:
                    SingleAccountMediumView(account: firstAccount)
                default:
                    SmallAccountView(account: firstAccount)
                }
            } else {
                EmptyLimitView(message: "Waiting for Codex")
            }
        }
        .foregroundStyle(CodexTheme.textPrimary)
        .tint(CodexTheme.primaryLight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SmallAccountView: View {
    let account: CodexAccountSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AccountWidgetHeader(account: account, compact: true)

            if let limits = account.limits, let first = limits.windows.first {
                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .lastTextBaseline, spacing: 5) {
                        Text("\(first.remainingPercent)%")
                            .font(CodexType.font(size: 37, weight: .semibold, relativeTo: .largeTitle))
                            .monospacedDigit()
                            .minimumScaleFactor(0.8)
                            .lineLimit(1)
                            .foregroundStyle(LimitPalette.color(for: first.remainingPercent))
                        Text("LEFT")
                            .font(CodexType.micro)
                            .tracking(0.8)
                            .foregroundStyle(CodexTheme.textSecondary)
                        Spacer(minLength: 0)
                    }

                    Text(first.title.uppercased())
                        .font(CodexType.micro)
                        .tracking(1)
                        .foregroundStyle(CodexTheme.textSecondary)

                    CodexLimitTrack(remaining: first.remainingPercent, height: 6)

                    if let reset = first.resetsAt {
                        Text("RESET \(reset, style: .relative)")
                            .font(CodexType.micro)
                            .tracking(0.35)
                            .monospacedDigit()
                            .foregroundStyle(CodexTheme.textSecondary)
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    SignalDot(color: LimitPalette.color(for: first.remainingPercent))
                    if !limits.resetCredits.isEmpty {
                        Text("\(limits.resetCredits.count) CREDITS")
                    } else {
                        Text("SYNCED")
                    }
                    Spacer(minLength: 2)
                    if let expiration = limits.nextExpiringResetCredit?.expiresAt {
                        Text(expiration.formatted(.dateTime.month(.abbreviated).day()))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
                .font(CodexType.micro)
                .tracking(0.45)
                .foregroundStyle(CodexTheme.textSecondary)
            } else {
                EmptyLimitView(message: account.errorMessage ?? "No limits")
            }
        }
    }
}

private struct SingleAccountMediumView: View {
    let account: CodexAccountSnapshot

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                AccountWidgetHeader(account: account, compact: false)
                Spacer()

                if let limits = account.limits {
                    CreditBadge(count: limits.resetCredits.count)
                    Text("UPDATED \(limits.fetchedAt, style: .relative)")
                        .font(CodexType.micro)
                        .tracking(0.5)
                        .monospacedDigit()
                        .foregroundStyle(limits.isStale ? CodexTheme.warning : CodexTheme.textSecondary)
                }
            }
            .frame(width: 105, alignment: .leading)

            Rectangle()
                .fill(CodexTheme.hairline)
                .frame(width: 1)

            if let limits = account.limits {
                HStack(alignment: .center, spacing: 18) {
                    ForEach(limits.windows.prefix(2)) { window in
                        LimitRing(window: window, compact: true)
                            .frame(maxWidth: .infinity)
                    }
                }

                if let expiration = limits.nextExpiringResetCredit?.expiresAt {
                    Rectangle()
                        .fill(CodexTheme.hairline)
                        .frame(width: 1)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("NEXT CREDIT")
                            .font(CodexType.micro)
                            .tracking(0.8)
                            .foregroundStyle(CodexTheme.textSecondary)
                        Text(expiration, style: .relative)
                            .font(CodexType.body)
                            .monospacedDigit()
                            .lineLimit(2)
                    }
                    .frame(width: 72, alignment: .leading)
                }
            } else {
                EmptyLimitView(message: account.errorMessage ?? "No limits")
            }
        }
    }
}

private struct MultiAccountMediumView: View {
    let dashboard: CodexDashboardSnapshot

    var body: some View {
        HStack(spacing: 12) {
            ForEach(dashboard.accountsForWidget(limit: 2)) { account in
                CompactAccountCard(account: account)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct CompactAccountCard: View {
    let account: CodexAccountSnapshot

    var body: some View {
        CodexGlassCard(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 9) {
                AccountWidgetHeader(account: account, compact: true)

                if let limits = account.limits {
                    ForEach(limits.windows.prefix(1)) { window in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .lastTextBaseline) {
                                Text(window.title.uppercased())
                                    .font(CodexType.micro)
                                    .tracking(0.8)
                                    .foregroundStyle(CodexTheme.textSecondary)
                                Spacer()
                                Text("\(window.remainingPercent)%")
                                    .font(CodexType.font(size: 25, weight: .semibold, relativeTo: .title2))
                                    .monospacedDigit()
                                    .foregroundStyle(LimitPalette.color(for: window.remainingPercent))
                            }

                            CodexLimitTrack(remaining: window.remainingPercent, height: 5)

                            if let reset = window.resetsAt {
                                Text("RESET \(reset, style: .relative)")
                                    .font(CodexType.micro)
                                    .tracking(0.45)
                                    .monospacedDigit()
                                    .foregroundStyle(CodexTheme.textSecondary)
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 5) {
                        SignalDot(color: CodexTheme.primaryLight)
                        Text("\(limits.resetCredits.count) RESET")
                        Spacer()
                        if let expiry = limits.nextExpiringResetCredit?.expiresAt {
                            Text(expiry.formatted(.dateTime.month(.abbreviated).day()))
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                    .font(CodexType.micro)
                    .tracking(0.35)
                    .foregroundStyle(CodexTheme.textSecondary)
                }
            }
            .padding(12)
        }
    }
}

private struct MultiAccountLargeView: View {
    let dashboard: CodexDashboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: dashboard.accounts.count >= 3 ? 7 : 12) {
            HStack(spacing: 9) {
                CodexAccountGlyph(size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text("CODEX / LIMITS")
                        .font(CodexType.micro)
                        .tracking(1.25)
                        .foregroundStyle(CodexTheme.primaryLight)
                    Text("Account signals")
                        .font(CodexType.title)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(dashboard.accounts.count) CONNECTED")
                        .font(CodexType.micro)
                        .tracking(0.65)
                    Text(dashboard.updatedAt, style: .relative)
                        .font(CodexType.caption)
                        .monospacedDigit()
                }
                .foregroundStyle(CodexTheme.textSecondary)
            }

            ForEach(dashboard.accountsForWidget(limit: 3)) { account in
                WideAccountRow(account: account, dense: dashboard.accounts.count >= 3)
            }

            if dashboard.accounts.count > 3 {
                Text("+\(dashboard.accounts.count - 3) MORE ACCOUNTS IN MENU BAR")
                    .font(CodexType.micro)
                    .tracking(0.55)
                    .foregroundStyle(CodexTheme.textSecondary)
            }
        }
    }
}

private struct WideAccountRow: View {
    let account: CodexAccountSnapshot
    let dense: Bool

    var body: some View {
        CodexGlassCard(cornerRadius: 15) {
            VStack(alignment: .leading, spacing: dense ? 5 : 8) {
                HStack(alignment: .center) {
                    AccountWidgetHeader(account: account, compact: true)
                    Spacer()
                    if let plan = account.limits?.normalizedPlan {
                        Text(plan.uppercased())
                            .font(CodexType.micro)
                            .tracking(0.7)
                            .foregroundStyle(CodexTheme.primaryLight)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(CodexTheme.primary.opacity(0.16), in: Capsule())
                    }
                }

                if let limits = account.limits {
                    HStack(spacing: 18) {
                        ForEach(limits.windows.prefix(2)) { window in
                            CompactLimitBar(window: window, showsReset: !dense)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    if !limits.resetCredits.isEmpty {
                        HStack(spacing: 6) {
                            SignalDot(color: CodexTheme.primaryLight)
                            Text("\(limits.resetCredits.count) RESET CREDITS")
                            Text("/")
                                .foregroundStyle(CodexTheme.primaryLight.opacity(0.55))
                            Text(expirationSummary(limits.resetCredits))
                                .lineLimit(1)
                        }
                        .font(CodexType.micro)
                        .tracking(0.3)
                        .foregroundStyle(CodexTheme.textSecondary)
                    }
                } else {
                    Label(account.errorMessage ?? "No limit data", systemImage: "exclamationmark.triangle")
                        .font(CodexType.caption)
                        .foregroundStyle(CodexTheme.warning)
                }
            }
            .padding(dense ? 8 : 11)
        }
    }

    private func expirationSummary(_ credits: [CodexResetCredit]) -> String {
        let values = credits.prefix(4).map { credit in
            credit.expiresAt?.formatted(.dateTime.month(.abbreviated).day()) ?? "No expiry"
        }
        let suffix = credits.count > values.count ? " · +\(credits.count - values.count)" : ""
        return "EXPIRES " + values.joined(separator: " · ") + suffix
    }
}

private struct AccountWidgetHeader: View {
    let account: CodexAccountSnapshot
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                CodexAccountGlyph(size: compact ? 22 : 27)
                Text(account.displayName)
                    .font(compact ? CodexType.body : CodexType.title)
                    .lineLimit(1)
                if account.errorMessage != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(CodexTheme.warning)
                }
            }
            if !compact, let email = account.email, email != account.displayName {
                Text(email)
                    .font(CodexType.micro)
                    .foregroundStyle(CodexTheme.textSecondary)
                    .lineLimit(1)
                    .padding(.leading, 34)
            }
        }
    }
}

private struct CompactLimitBar: View {
    let window: CodexLimitWindow
    var showsReset = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .lastTextBaseline) {
                Text(window.title.uppercased())
                    .tracking(0.65)
                    .foregroundStyle(CodexTheme.textSecondary)
                Spacer()
                Text("\(window.remainingPercent)%")
                    .monospacedDigit()
                    .foregroundStyle(LimitPalette.color(for: window.remainingPercent))
            }
            .font(CodexType.micro)

            CodexLimitTrack(remaining: window.remainingPercent, height: 5)

            if showsReset, let reset = window.resetsAt {
                Text("RESET \(reset, style: .relative)")
                    .font(CodexType.micro)
                    .tracking(0.35)
                    .monospacedDigit()
                    .foregroundStyle(CodexTheme.textSecondary)
            }
        }
    }
}

private struct CreditBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            SignalDot(color: CodexTheme.primaryLight)
            Text("\(count) RESET\(count == 1 ? "" : "S")")
                .font(CodexType.micro)
                .tracking(0.5)
        }
        .foregroundStyle(CodexTheme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.075), in: Capsule())
        .overlay(Capsule().stroke(CodexTheme.hairline, lineWidth: 0.7))
    }
}

private struct SignalDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 5, height: 5)
            .shadow(color: color.opacity(0.8), radius: 3)
            .accessibilityHidden(true)
    }
}
