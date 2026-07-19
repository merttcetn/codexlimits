import Combine
import Foundation
import ServiceManagement
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var dashboard: CodexDashboardSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published var profiles: [CodexAccountProfile] {
        didSet { persistProfiles() }
    }
    @Published var codexPath: String {
        didSet { UserDefaults.standard.set(codexPath, forKey: Self.codexPathKey) }
    }
    @Published var refreshIntervalMinutes: Int {
        didSet {
            UserDefaults.standard.set(refreshIntervalMinutes, forKey: Self.refreshIntervalKey)
            restartMonitoring()
        }
    }
    @Published private(set) var launchAtLoginEnabled: Bool

    private static let codexPathKey = "codex-executable-path"
    private static let refreshIntervalKey = "refresh-interval-minutes"
    private static let profilesKey = "codex-account-profiles-v1"
    private var monitoringTask: Task<Void, Never>?

    init() {
        dashboard = SnapshotStore.load()
        if let data = UserDefaults.standard.data(forKey: Self.profilesKey),
           let savedProfiles = try? JSONDecoder().decode([CodexAccountProfile].self, from: data),
           !savedProfiles.isEmpty {
            profiles = savedProfiles
        } else {
            profiles = [.defaultProfile]
        }
        let savedPath = UserDefaults.standard.string(forKey: Self.codexPathKey)
        codexPath = savedPath ?? CodexExecutableLocator.locate()?.path ?? ""
        let savedInterval = UserDefaults.standard.integer(forKey: Self.refreshIntervalKey)
        refreshIntervalMinutes = savedInterval == 0 ? 5 : savedInterval
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    deinit {
        monitoringTask?.cancel()
    }

    func startMonitoring() {
        guard monitoringTask == nil else { return }
        monitoringTask = Task { [weak self] in
            guard let self else { return }
            await refresh()
            while !Task.isCancelled {
                let seconds = max(1, refreshIntervalMinutes) * 60
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                await refresh()
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

        guard let executable = CodexExecutableLocator.locate(preferredPath: codexPath) else {
            errorMessage = CodexAppServerError.executableNotFound.localizedDescription
            return
        }

        if codexPath != executable.path {
            codexPath = executable.path
        }

        do {
            let client = CodexAppServerClient(executableURL: executable)
            let activeProfiles = profiles
            let previousAccounts = Dictionary(uniqueKeysWithValues: (dashboard?.accounts ?? []).map { ($0.id, $0) })
            let outcomes = await withTaskGroup(of: AccountRefreshOutcome.self, returning: [AccountRefreshOutcome].self) { group in
                for profile in activeProfiles {
                    group.addTask {
                        do {
                            return AccountRefreshOutcome(
                                profile: profile,
                                snapshot: try await client.fetchAccount(profile: profile),
                                errorMessage: nil
                            )
                        } catch {
                            return AccountRefreshOutcome(
                                profile: profile,
                                snapshot: nil,
                                errorMessage: error.localizedDescription
                            )
                        }
                    }
                }

                var values: [AccountRefreshOutcome] = []
                for await outcome in group {
                    values.append(outcome)
                }
                return values
            }

            let byID = Dictionary(uniqueKeysWithValues: outcomes.map { ($0.profile.id, $0) })
            let accounts = activeProfiles.map { profile in
                guard let outcome = byID[profile.id] else {
                    return CodexAccountSnapshot(
                        id: profile.id,
                        name: profile.name,
                        email: nil,
                        limits: nil,
                        errorMessage: "Refresh did not complete"
                    )
                }
                if let snapshot = outcome.snapshot {
                    return snapshot
                }
                let previous = previousAccounts[profile.id]
                return CodexAccountSnapshot(
                    id: profile.id,
                    name: profile.name,
                    email: previous?.email,
                    limits: previous?.limits,
                    errorMessage: outcome.errorMessage
                )
            }

            let freshDashboard = CodexDashboardSnapshot(updatedAt: .now, accounts: accounts)
            try SnapshotStore.save(freshDashboard)
            dashboard = freshDashboard
            if accounts.allSatisfy({ $0.limits == nil }) {
                errorMessage = "No configured Codex account could be refreshed."
            }
            WidgetCenter.shared.reloadTimelines(ofKind: CodexLimitsWidgetKind.value)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func findCodexAutomatically() {
        if let path = CodexExecutableLocator.locate()?.path {
            codexPath = path
            errorMessage = nil
        } else {
            errorMessage = CodexAppServerError.executableNotFound.localizedDescription
        }
    }

    func addProfile(codexHome: URL) {
        let standardizedPath = codexHome.standardizedFileURL.path
        guard !profiles.contains(where: { $0.expandedCodexHome == standardizedPath }) else {
            errorMessage = "That account folder is already configured."
            return
        }

        profiles.append(
            CodexAccountProfile(
                id: UUID().uuidString,
                name: codexHome.lastPathComponent.replacingOccurrences(of: ".codex", with: "Codex"),
                codexHome: standardizedPath
            )
        )
        Task { await refresh() }
    }

    func removeProfile(id: String) {
        guard id != CodexAccountProfile.defaultID else { return }
        profiles.removeAll { $0.id == id }
        if let dashboard {
            let updated = CodexDashboardSnapshot(
                updatedAt: .now,
                accounts: dashboard.accounts.filter { $0.id != id }
            )
            try? SnapshotStore.save(updated)
            self.dashboard = updated
            WidgetCenter.shared.reloadTimelines(ofKind: CodexLimitsWidgetKind.value)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        } catch {
            errorMessage = "Could not update Launch at Login: \(error.localizedDescription)"
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        }
    }

    private func restartMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        startMonitoring()
    }

    private func persistProfiles() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: Self.profilesKey)
    }
}

private struct AccountRefreshOutcome: Sendable {
    let profile: CodexAccountProfile
    let snapshot: CodexAccountSnapshot?
    let errorMessage: String?
}

enum CodexLimitsWidgetKind {
    static let value = "CodexLimitsWidget"
}
