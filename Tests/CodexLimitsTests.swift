import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import CodexLimitsCore
#endif

@Suite("Codex Limits")
struct CodexLimitsTests {
    @Test("Dashboard preview contains simultaneous accounts")
    func dashboardPreviewContainsMultipleAccounts() {
        #expect(CodexDashboardSnapshot.preview.accounts.count == 2)
        #expect(CodexDashboardSnapshot.preview.successfulAccounts.count == 2)
        #expect(CodexAccountProfile.defaultProfile.expandedCodexHome == nil)
    }

    @Test("Remaining percentage is clamped")
    func remainingPercentIsClamped() {
        let normal = CodexLimitWindow(id: "normal", title: "Weekly", usedPercent: 44, resetsAt: nil, durationMinutes: 10_080)
        let exhausted = CodexLimitWindow(id: "over", title: "Weekly", usedPercent: 140, resetsAt: nil, durationMinutes: 10_080)

        #expect(normal.remainingPercent == 56)
        #expect(exhausted.remainingPercent == 0)
    }

    @Test("Widgets prioritize accounts with the most usable capacity")
    func widgetAccountPriorityUsesTheMostConstrainedWindow() {
        let dashboard = CodexDashboardSnapshot(
            updatedAt: .now,
            accounts: [
                account(id: "misleading", remaining: [95, 5]),
                account(id: "balanced", remaining: [70, 60]),
                account(id: "middle", remaining: [55]),
                account(id: "exhausted", remaining: [0])
            ]
        )

        #expect(dashboard.accountsForWidget(limit: 3).map(\.id) == ["balanced", "middle", "misleading"])
        #expect(dashboard.firstAvailableAccount?.id == "balanced")
    }

    @Test("App-server response filters and sorts reset credits")
    func appServerResponseDecodesAndSortsAvailableResetCredits() throws {
        let json = #"""
        {
          "id": 1,
          "result": {
            "rateLimits": {
              "limitId": "codex",
              "planType": "plus",
              "primary": {"usedPercent": 44, "windowDurationMins": 10080, "resetsAt": 2200000000},
              "secondary": {"usedPercent": 12, "windowDurationMins": 300, "resetsAt": 2100000000},
              "credits": {"balance": "0"}
            },
            "rateLimitsByLimitId": null,
            "rateLimitResetCredits": {
              "availableCount": 3,
              "credits": [
                {"id": "late", "status": "available", "expiresAt": 2300000000, "title": "Full reset"},
                {"id": "spent", "status": "redeemed", "expiresAt": 2250000000, "title": "Full reset"},
                {"id": "early", "status": "available", "expiresAt": 2200000000, "title": "Full reset"}
              ]
            }
          }
        }
        """#

        let snapshot = try CodexAppServerClient.decodeRateLimitResponseJSON(json)

        #expect(snapshot.plan == "plus")
        #expect(snapshot.windows.map(\.title) == ["5-hour", "Weekly"])
        #expect(snapshot.resetCredits.count == 2)
        let firstExpiration = try #require(snapshot.resetCredits[0].expiresAt)
        let secondExpiration = try #require(snapshot.resetCredits[1].expiresAt)
        #expect(firstExpiration < secondExpiration)
    }

    @Test("App-server usage response normalizes daily buckets")
    func appServerUsageResponseNormalizesBuckets() throws {
        let json = #"""
        {
          "id": 3,
          "result": {
            "dailyUsageBuckets": [
              {"startDate": "2026-07-19", "tokens": 800000},
              {"startDate": "2026-07-18", "tokens": -5},
              {"startDate": "2026-07-19", "tokens": 1200000}
            ],
            "summary": {
              "currentStreakDays": 4,
              "lifetimeTokens": 9500000,
              "longestRunningTurnSec": 920,
              "longestStreakDays": 12,
              "peakDailyTokens": 1600000
            }
          }
        }
        """#

        let usage = try CodexAppServerClient.decodeUsageResponseJSON(json)

        #expect(usage.dailyUsageBuckets.map(\.startDate) == ["2026-07-18", "2026-07-19"])
        #expect(usage.dailyUsageBuckets.map(\.tokens) == [0, 1_200_000])
        #expect(usage.summary.currentStreakDays == 4)
        #expect(usage.summary.peakDailyTokens == 1_600_000)
    }

    @Test("Usage weeks fill missing dates and calculate contextual summaries")
    func usageWeeksAreCalendarAligned() throws {
        let calendar = testCalendar
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 15)))
        let usage = CodexUsageSnapshot(
            fetchedAt: now,
            dailyUsageBuckets: [
                CodexUsageDay(startDate: "2026-07-13", tokens: 100),
                CodexUsageDay(startDate: "2026-07-15", tokens: 300),
                CodexUsageDay(startDate: "2026-07-19", tokens: 200),
                CodexUsageDay(startDate: "2026-07-20", tokens: 450)
            ],
            summary: usageSummary(streak: 6)
        )

        let current = try #require(usage.week(offset: 0, calendar: calendar, now: now))
        #expect(current.todayTokens == 450)
        #expect(current.currentStreakDays == 6)
        #expect(current.days.count == 7)

        let previous = try #require(usage.week(offset: -1, calendar: calendar, now: now))
        #expect(previous.days.map(\.tokens) == [100, 0, 300, 0, 0, 0, 200])
        #expect(previous.totalTokens == 600)
        #expect(previous.peakTokens == 300)
        #expect(previous.rangeLabel(locale: Locale(identifier: "en_US_POSIX"), calendar: calendar) == "JUL 13–19")
        #expect(usage.earliestWeekOffset(calendar: calendar, now: now) == -1)
    }

    @Test("Usage week navigation clamps to available history")
    func usageWeekNavigationClampsToHistory() throws {
        let calendar = testCalendar
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 15)))
        let account = CodexAccountSnapshot(
            id: "usage",
            name: "Usage",
            email: nil,
            limits: .preview,
            usage: CodexUsageSnapshot(
                fetchedAt: now,
                dailyUsageBuckets: [CodexUsageDay(startDate: "2026-07-06", tokens: 100)],
                summary: usageSummary(streak: 1)
            ),
            errorMessage: nil
        )
        let dashboard = CodexDashboardSnapshot(updatedAt: now, accounts: [account])

        #expect(dashboard.clampedUsageWeekOffset(2, calendar: calendar, now: now) == 0)
        #expect(dashboard.clampedUsageWeekOffset(-1, calendar: calendar, now: now) == -1)
        #expect(dashboard.clampedUsageWeekOffset(-20, calendar: calendar, now: now) == -2)
    }

    @Test("Snapshots without usage remain decodable")
    func legacyDashboardDecodesWithoutUsage() throws {
        let json = #"""
        {
          "updatedAt": 0,
          "accounts": [
            {
              "id": "default",
              "name": "Default",
              "email": null,
              "limits": null,
              "errorMessage": null
            }
          ]
        }
        """#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let dashboard = try decoder.decode(CodexDashboardSnapshot.self, from: Data(json.utf8))
        #expect(dashboard.accounts.first?.usage == nil)
    }

    @Test("Token counts use compact readable labels")
    func tokenCountsFormatCompactly() {
        let locale = Locale(identifier: "en_US_POSIX")
        #expect(CodexUsageFormatting.compactTokens(845, locale: locale) == "845")
        #expect(CodexUsageFormatting.compactTokens(12_400, locale: locale) == "12K")
        #expect(CodexUsageFormatting.compactTokens(1_240_000, locale: locale) == "1.2M")
        #expect(CodexUsageFormatting.tokenLabel(1_240_000, locale: locale) == "1.2M TOKENS")
    }

    private func account(id: String, remaining: [Int]) -> CodexAccountSnapshot {
        CodexAccountSnapshot(
            id: id,
            name: id,
            email: nil,
            limits: CodexLimitSnapshot(
                fetchedAt: .now,
                plan: "plus",
                windows: remaining.enumerated().map { index, percent in
                    CodexLimitWindow(
                        id: "\(id)-\(index)",
                        title: "Window \(index)",
                        usedPercent: 100 - percent,
                        resetsAt: nil,
                        durationMinutes: nil
                    )
                },
                creditBalance: nil,
                resetCredits: []
            ),
            errorMessage: nil
        )
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    private func usageSummary(streak: Int64) -> CodexUsageSummary {
        CodexUsageSummary(
            currentStreakDays: streak,
            lifetimeTokens: nil,
            longestRunningTurnSec: nil,
            longestStreakDays: nil,
            peakDailyTokens: nil
        )
    }
}
