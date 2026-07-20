import Foundation

struct CodexAccountProfile: Codable, Equatable, Identifiable, Sendable {
    static let defaultID = "default"

    var id: String
    var name: String
    var codexHome: String?

    static let defaultProfile = CodexAccountProfile(id: defaultID, name: "Default", codexHome: nil)

    var expandedCodexHome: String? {
        guard let codexHome, !codexHome.isEmpty else { return nil }
        return (codexHome as NSString).expandingTildeInPath
    }
}

struct CodexAccountSnapshot: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let email: String?
    let limits: CodexLimitSnapshot?
    let usage: CodexUsageSnapshot?
    let errorMessage: String?

    init(
        id: String,
        name: String,
        email: String?,
        limits: CodexLimitSnapshot?,
        usage: CodexUsageSnapshot? = nil,
        errorMessage: String?
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.limits = limits
        self.usage = usage
        self.errorMessage = errorMessage
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return email ?? "Codex Account"
    }
}

struct CodexDashboardSnapshot: Codable, Equatable, Sendable {
    let updatedAt: Date
    let accounts: [CodexAccountSnapshot]

    static let preview = CodexDashboardSnapshot(
        updatedAt: .now,
        accounts: [
            CodexAccountSnapshot(
                id: "personal",
                name: "Personal",
                email: "personal@example.com",
                limits: .preview,
                usage: .preview,
                errorMessage: nil
            ),
            CodexAccountSnapshot(
                id: "work",
                name: "Work",
                email: "work@example.com",
                limits: CodexLimitSnapshot(
                    fetchedAt: .now,
                    plan: "Business",
                    windows: [
                        CodexLimitWindow(
                            id: "work-300",
                            title: "5-hour",
                            usedPercent: 61,
                            resetsAt: .now.addingTimeInterval(74 * 60),
                            durationMinutes: 300
                        ),
                        CodexLimitWindow(
                            id: "work-10080",
                            title: "Weekly",
                            usedPercent: 23,
                            resetsAt: .now.addingTimeInterval(5 * 24 * 60 * 60),
                            durationMinutes: 10_080
                        )
                    ],
                    creditBalance: nil,
                    resetCredits: []
                ),
                usage: .preview,
                errorMessage: nil
            )
        ]
    )
}

struct CodexLimitSnapshot: Codable, Equatable, Sendable {
    let fetchedAt: Date
    let plan: String?
    let windows: [CodexLimitWindow]
    let creditBalance: String?
    let resetCredits: [CodexResetCredit]

    static let preview = CodexLimitSnapshot(
        fetchedAt: .now,
        plan: "Plus",
        windows: [
            CodexLimitWindow(
                id: "codex-300",
                title: "5-hour",
                usedPercent: 28,
                resetsAt: .now.addingTimeInterval(2 * 60 * 60 + 18 * 60),
                durationMinutes: 300
            ),
            CodexLimitWindow(
                id: "codex-10080",
                title: "Weekly",
                usedPercent: 44,
                resetsAt: .now.addingTimeInterval(4 * 24 * 60 * 60),
                durationMinutes: 10_080
            )
        ],
        creditBalance: "0",
        resetCredits: [
            CodexResetCredit(id: "preview-1", title: "Full reset", expiresAt: .now.addingTimeInterval(9 * 24 * 60 * 60)),
            CodexResetCredit(id: "preview-2", title: "Full reset", expiresAt: .now.addingTimeInterval(16 * 24 * 60 * 60)),
            CodexResetCredit(id: "preview-3", title: "Full reset", expiresAt: .now.addingTimeInterval(28 * 24 * 60 * 60))
        ]
    )
}

struct CodexResetCredit: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let expiresAt: Date?
}

struct CodexLimitWindow: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let usedPercent: Int
    let resetsAt: Date?
    let durationMinutes: Int?

    var remainingPercent: Int {
        max(0, min(100, 100 - usedPercent))
    }
}

struct CodexUsageSnapshot: Codable, Equatable, Sendable {
    let fetchedAt: Date
    let dailyUsageBuckets: [CodexUsageDay]
    let summary: CodexUsageSummary

    static let preview: CodexUsageSnapshot = {
        let calendar = Calendar.autoupdatingCurrent
        let values: [Int64] = [420_000, 730_000, 510_000, 1_180_000, 860_000, 1_420_000, 940_000,
                               680_000, 1_060_000, 890_000, 1_310_000, 1_520_000, 760_000, 1_240_000]
        let buckets = values.enumerated().compactMap { index, tokens -> CodexUsageDay? in
            guard let date = calendar.date(byAdding: .day, value: index - values.count + 1, to: .now) else {
                return nil
            }
            return CodexUsageDay(startDate: CodexUsageCalendar.dayKey(for: date, calendar: calendar), tokens: tokens)
        }
        return CodexUsageSnapshot(
            fetchedAt: .now,
            dailyUsageBuckets: buckets,
            summary: CodexUsageSummary(
                currentStreakDays: 6,
                lifetimeTokens: 48_600_000,
                longestRunningTurnSec: 1_842,
                longestStreakDays: 19,
                peakDailyTokens: 2_140_000
            )
        )
    }()

    func week(
        offset: Int,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) -> CodexUsageWeek? {
        guard !dailyUsageBuckets.isEmpty,
              let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let weekStart = calendar.date(byAdding: .weekOfYear, value: min(0, offset), to: currentWeekStart) else {
            return nil
        }

        let tokensByDay = Dictionary(
            dailyUsageBuckets.map { ($0.startDate, max(0, $0.tokens)) },
            uniquingKeysWith: { _, latest in latest }
        )
        let days = (0..<7).compactMap { index -> CodexUsageWeek.Day? in
            guard let date = calendar.date(byAdding: .day, value: index, to: weekStart) else { return nil }
            let key = CodexUsageCalendar.dayKey(for: date, calendar: calendar)
            return CodexUsageWeek.Day(date: date, tokens: tokensByDay[key] ?? 0)
        }
        guard days.count == 7, let weekEnd = days.last?.date else { return nil }

        return CodexUsageWeek(
            offset: min(0, offset),
            startDate: weekStart,
            endDate: weekEnd,
            days: days,
            currentStreakDays: summary.currentStreakDays,
            calendar: calendar,
            now: now
        )
    }

    func earliestWeekOffset(
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) -> Int {
        guard let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let earliestDate = dailyUsageBuckets.compactMap({
                  CodexUsageCalendar.date(from: $0.startDate, calendar: calendar)
              }).min(),
              let earliestWeekStart = calendar.dateInterval(of: .weekOfYear, for: earliestDate)?.start else {
            return 0
        }

        let days = calendar.dateComponents([.day], from: earliestWeekStart, to: currentWeekStart).day ?? 0
        return min(0, -(max(0, days) / 7))
    }
}

struct CodexUsageDay: Codable, Equatable, Identifiable, Sendable {
    let startDate: String
    let tokens: Int64

    var id: String { startDate }
}

struct CodexUsageSummary: Codable, Equatable, Sendable {
    let currentStreakDays: Int64?
    let lifetimeTokens: Int64?
    let longestRunningTurnSec: Int64?
    let longestStreakDays: Int64?
    let peakDailyTokens: Int64?
}

struct CodexUsageWeek: Equatable, Sendable {
    struct Day: Equatable, Identifiable, Sendable {
        let date: Date
        let tokens: Int64

        var id: Date { date }
    }

    let offset: Int
    let startDate: Date
    let endDate: Date
    let days: [Day]
    let currentStreakDays: Int64?
    let isCurrentWeek: Bool
    let todayTokens: Int64
    let totalTokens: Int64
    let peakTokens: Int64

    init(
        offset: Int,
        startDate: Date,
        endDate: Date,
        days: [Day],
        currentStreakDays: Int64?,
        calendar: Calendar,
        now: Date
    ) {
        self.offset = offset
        self.startDate = startDate
        self.endDate = endDate
        self.days = days
        self.currentStreakDays = currentStreakDays
        isCurrentWeek = offset == 0
        todayTokens = days.first(where: { calendar.isDate($0.date, inSameDayAs: now) })?.tokens ?? 0
        totalTokens = days.reduce(0) { $0 + $1.tokens }
        peakTokens = days.map(\.tokens).max() ?? 0
    }

    func rangeLabel(locale: Locale = .autoupdatingCurrent, calendar: Calendar = .autoupdatingCurrent) -> String {
        let monthFormatter = DateFormatter()
        monthFormatter.locale = locale
        monthFormatter.calendar = calendar
        monthFormatter.timeZone = calendar.timeZone
        monthFormatter.setLocalizedDateFormatFromTemplate("MMM")

        let dayFormatter = DateFormatter()
        dayFormatter.locale = locale
        dayFormatter.calendar = calendar
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.setLocalizedDateFormatFromTemplate("d")

        let startMonth = monthFormatter.string(from: startDate)
        let endMonth = monthFormatter.string(from: endDate)
        let startDay = dayFormatter.string(from: startDate)
        let endDay = dayFormatter.string(from: endDate)
        let value = startMonth == endMonth
            ? "\(startMonth) \(startDay)–\(endDay)"
            : "\(startMonth) \(startDay)–\(endMonth) \(endDay)"
        return value.uppercased(with: locale)
    }
}

enum CodexUsageFormatting {
    static func compactTokens(_ tokens: Int64, locale: Locale = .autoupdatingCurrent) -> String {
        let value = Double(max(0, tokens))
        let scaled: Double
        let suffix: String
        switch value {
        case 1_000_000_000...:
            scaled = value / 1_000_000_000
            suffix = "B"
        case 1_000_000...:
            scaled = value / 1_000_000
            suffix = "M"
        case 1_000...:
            scaled = value / 1_000
            suffix = "K"
        default:
            return Int64(value).formatted(.number.locale(locale))
        }

        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = scaled < 10 ? 1 : 0
        return (formatter.string(from: NSNumber(value: scaled)) ?? String(format: "%.1f", scaled)) + suffix
    }

    static func tokenLabel(_ tokens: Int64, locale: Locale = .autoupdatingCurrent) -> String {
        "\(compactTokens(tokens, locale: locale)) TOKENS"
    }
}

enum CodexUsageCalendar {
    static func date(from dayKey: String, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    static func dayKey(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let components = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

extension CodexLimitSnapshot {
    var normalizedPlan: String? {
        guard let plan, !plan.isEmpty else { return nil }
        return plan.prefix(1).uppercased() + plan.dropFirst()
    }

    var isStale: Bool {
        Date.now.timeIntervalSince(fetchedAt) > 30 * 60
    }

    var nextExpiringResetCredit: CodexResetCredit? {
        resetCredits.first
    }
}

extension CodexDashboardSnapshot {
    var successfulAccounts: [CodexAccountSnapshot] {
        accounts.filter { $0.limits != nil }
    }

    var firstAvailableAccount: CodexAccountSnapshot? {
        accountsForWidget(limit: 1).first
    }

    func accountsForWidget(limit: Int) -> [CodexAccountSnapshot] {
        guard limit > 0 else { return [] }

        let indexedSuccessful = accounts.enumerated().filter { $0.element.limits != nil }
        let selectedSuccessful: [CodexAccountSnapshot]

        if indexedSuccessful.count > limit {
            selectedSuccessful = indexedSuccessful.sorted { lhs, rhs in
                let lhsScore = lhs.element.widgetCapacityScore
                let rhsScore = rhs.element.widgetCapacityScore

                if lhsScore.limiting != rhsScore.limiting {
                    return lhsScore.limiting > rhsScore.limiting
                }
                if lhsScore.total != rhsScore.total {
                    return lhsScore.total > rhsScore.total
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        } else {
            selectedSuccessful = indexedSuccessful.map(\.element)
        }

        let failedAccounts = accounts.filter { $0.limits == nil }
        return Array((selectedSuccessful + failedAccounts).prefix(limit))
    }

    var hasUsage: Bool {
        accounts.contains { $0.usage?.dailyUsageBuckets.isEmpty == false }
    }

    func earliestUsageWeekOffset(
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) -> Int {
        accounts.compactMap { account in
            account.usage?.dailyUsageBuckets.isEmpty == false
                ? account.usage?.earliestWeekOffset(calendar: calendar, now: now)
                : nil
        }.min() ?? 0
    }

    func clampedUsageWeekOffset(
        _ requestedOffset: Int,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) -> Int {
        max(earliestUsageWeekOffset(calendar: calendar, now: now), min(0, requestedOffset))
    }

    func usageWeek(
        offset: Int,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) -> CodexUsageWeek? {
        accounts.compactMap(\.usage).first(where: { !$0.dailyUsageBuckets.isEmpty })?
            .week(offset: clampedUsageWeekOffset(offset, calendar: calendar, now: now), calendar: calendar, now: now)
    }
}

private extension CodexAccountSnapshot {
    var widgetCapacityScore: (limiting: Int, total: Int) {
        guard let windows = limits?.windows, !windows.isEmpty else {
            return (-1, -1)
        }
        let remaining = windows.map(\.remainingPercent)
        return (remaining.min() ?? -1, remaining.reduce(0, +))
    }
}
