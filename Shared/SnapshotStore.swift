import Foundation

enum SnapshotStore {
    static let appGroupIdentifier = "group.com.mertcetin.codexlimits"
    private static let dashboardKey = "codex-dashboard-snapshot-v2"
    private static let legacySnapshotKey = "codex-limit-snapshot-v1"
    private static let usageWeekOffsetKey = "codex-usage-week-offset-v1"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static func load() -> CodexDashboardSnapshot? {
        if let data = defaults.data(forKey: dashboardKey),
           let dashboard = try? JSONDecoder().decode(CodexDashboardSnapshot.self, from: data) {
            return dashboard
        }

        guard let data = defaults.data(forKey: legacySnapshotKey),
              let legacy = try? JSONDecoder().decode(CodexLimitSnapshot.self, from: data) else {
            return nil
        }

        return CodexDashboardSnapshot(
            updatedAt: legacy.fetchedAt,
            accounts: [
                CodexAccountSnapshot(
                    id: CodexAccountProfile.defaultID,
                    name: "Default",
                    email: nil,
                    limits: legacy,
                    errorMessage: nil
                )
            ]
        )
    }

    static func save(_ dashboard: CodexDashboardSnapshot) throws {
        let data = try JSONEncoder().encode(dashboard)
        defaults.set(data, forKey: dashboardKey)
    }

    static func loadUsageWeekOffset() -> Int {
        min(0, defaults.integer(forKey: usageWeekOffsetKey))
    }

    static func saveUsageWeekOffset(_ offset: Int) {
        defaults.set(min(0, offset), forKey: usageWeekOffsetKey)
    }
}
