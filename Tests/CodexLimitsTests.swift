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
}
