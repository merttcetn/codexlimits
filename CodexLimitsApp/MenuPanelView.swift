import AppKit
import SwiftUI

struct MenuPanelView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            header

            if let dashboard = model.dashboard, !dashboard.accounts.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(dashboard.accounts) { account in
                            AccountMenuCard(account: account)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 620)
            } else {
                EmptyLimitView(message: model.errorMessage ?? "No account data yet")
                    .frame(height: 180)
            }

            if let error = model.errorMessage, model.dashboard != nil {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(CodexType.caption)
                    .foregroundStyle(CodexTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            footer
        }
        .padding(16)
        .frame(width: 390)
        .foregroundStyle(CodexTheme.textPrimary)
        .tint(CodexTheme.primaryLight)
        .background(CodexAuroraBackground())
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .shadow(color: CodexTheme.primary.opacity(0.45), radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 1) {
                Text("CODEX / LIMITS")
                    .font(CodexType.micro)
                    .tracking(1.25)
                    .foregroundStyle(CodexTheme.primaryLight)
                Text("Account signals")
                    .font(CodexType.title)
            }

            Spacer()

            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .tint(CodexTheme.primaryLight)
                    .accessibilityLabel("Refreshing Codex accounts")
            } else if let dashboard = model.dashboard {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(dashboard.accounts.count) CONNECTED")
                        .font(CodexType.micro)
                        .tracking(0.5)
                    Text(dashboard.updatedAt, style: .relative)
                        .font(CodexType.caption)
                        .monospacedDigit()
                }
                .foregroundStyle(CodexTheme.textSecondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                Task { await model.refresh() }
            } label: {
                Label(model.isRefreshing ? "Syncing…" : "Sync all", systemImage: "arrow.triangle.2.circlepath")
                    .font(CodexType.caption)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(CodexTheme.primary.opacity(0.22), in: Capsule())
                    .overlay(Capsule().stroke(CodexTheme.primaryLight.opacity(0.28), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .disabled(model.isRefreshing)

            Spacer()

            Button("Accounts") { openSettings() }
                .buttonStyle(CodexTextButtonStyle())
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(CodexTextButtonStyle())
        }
    }
}

private struct AccountMenuCard: View {
    let account: CodexAccountSnapshot

    var body: some View {
        CodexGlassCard(cornerRadius: 17) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .center, spacing: 8) {
                    CodexAccountGlyph(size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.displayName)
                            .font(CodexType.title)
                        if let email = account.email, email != account.displayName {
                            Text(email)
                                .font(CodexType.micro)
                                .foregroundStyle(CodexTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if let plan = account.limits?.normalizedPlan {
                        Text(plan.uppercased())
                            .font(CodexType.micro)
                            .tracking(0.8)
                            .foregroundStyle(CodexTheme.primaryLight)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(CodexTheme.primary.opacity(0.17), in: Capsule())
                    }
                    if account.errorMessage != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(CodexTheme.warning)
                            .help(account.errorMessage ?? "Refresh failed")
                    }
                }

                if let limits = account.limits, !limits.windows.isEmpty {
                    HStack(alignment: .center, spacing: 18) {
                        ForEach(limits.windows.prefix(2)) { window in
                            MenuLimitMetric(window: window)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    HStack(spacing: 7) {
                        Circle()
                            .fill(CodexTheme.primaryLight)
                            .frame(width: 6, height: 6)
                            .shadow(color: CodexTheme.primaryLight.opacity(0.75), radius: 4)
                        Text("\(limits.resetCredits.count) RESET CREDIT\(limits.resetCredits.count == 1 ? "" : "S")")
                            .font(CodexType.micro)
                            .tracking(0.5)
                        Spacer()
                        Text("SYNCED \(limits.fetchedAt, style: .relative)")
                            .font(CodexType.micro)
                            .tracking(0.35)
                            .monospacedDigit()
                            .foregroundStyle(limits.isStale ? CodexTheme.warning : CodexTheme.textSecondary)
                    }
                    .foregroundStyle(CodexTheme.textSecondary)

                    if !limits.resetCredits.isEmpty {
                        ResetCreditList(credits: limits.resetCredits)
                    }
                } else {
                    Label(account.errorMessage ?? "No limit data", systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(CodexType.caption)
                        .foregroundStyle(CodexTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                }
            }
            .padding(14)
        }
    }
}

private struct MenuLimitMetric: View {
    let window: CodexLimitWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .lastTextBaseline) {
                Text(window.title.uppercased())
                    .font(CodexType.micro)
                    .tracking(0.85)
                    .foregroundStyle(CodexTheme.textSecondary)
                Spacer()
                Text("\(window.remainingPercent)%")
                    .font(CodexType.font(size: 27, weight: .semibold, relativeTo: .title2))
                    .monospacedDigit()
                    .foregroundStyle(LimitPalette.color(for: window.remainingPercent))
            }

            CodexLimitTrack(remaining: window.remainingPercent, height: 6)

            if let reset = window.resetsAt {
                Text("RESETS \(reset, style: .relative)")
                    .font(CodexType.micro)
                    .tracking(0.4)
                    .monospacedDigit()
                    .foregroundStyle(CodexTheme.textSecondary)
            }
        }
    }
}

private struct ResetCreditList: View {
    let credits: [CodexResetCredit]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("EXPIRATION QUEUE")
                    .font(CodexType.micro)
                    .tracking(0.85)
                Spacer()
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption2)
            }
            .foregroundStyle(CodexTheme.textSecondary)

            ForEach(Array(credits.enumerated()), id: \.element.id) { index, credit in
                HStack(spacing: 8) {
                    Text(String(format: "%02d", index + 1))
                        .font(CodexType.micro)
                        .monospacedDigit()
                        .foregroundStyle(CodexTheme.primaryLight)
                    Rectangle()
                        .fill(CodexTheme.hairline)
                        .frame(height: 1)
                    if let expiration = credit.expiresAt {
                        Text(expiration.formatted(date: .abbreviated, time: .omitted))
                            .font(CodexType.caption)
                            .monospacedDigit()
                        Text(expiration, style: .relative)
                            .font(CodexType.micro)
                            .monospacedDigit()
                            .foregroundStyle(expiration.timeIntervalSinceNow < 3 * 24 * 60 * 60 ? CodexTheme.warning : CodexTheme.textSecondary)
                    } else {
                        Text("NO EXPIRY")
                            .font(CodexType.micro)
                            .foregroundStyle(CodexTheme.textSecondary)
                    }
                }
                .help(credit.expiresAt.map { "Expires \($0.formatted(date: .complete, time: .shortened))" } ?? "No expiration date")
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(CodexTheme.hairline, lineWidth: 0.7))
    }
}

private struct CodexTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CodexType.caption)
            .foregroundStyle(configuration.isPressed ? CodexTheme.primaryLight : CodexTheme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
    }
}
