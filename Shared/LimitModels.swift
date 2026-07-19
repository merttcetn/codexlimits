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
    let errorMessage: String?

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
