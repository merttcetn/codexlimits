import Foundation

struct CodexAppServerClient: Sendable {
    let executableURL: URL

    func fetchAccount(
        profile: CodexAccountProfile,
        timeout: Duration = .seconds(10)
    ) async throws -> CodexAccountSnapshot {
        if let home = profile.expandedCodexHome,
           !FileManager.default.fileExists(atPath: home) {
            throw CodexAppServerError.invalidProfileHome(home)
        }

        let session = AppServerSession(
            executableURL: executableURL,
            codexHome: profile.expandedCodexHome.map(URL.init(fileURLWithPath:))
        )

        return try await withThrowingTaskGroup(of: FetchedAccount.self) { group in
            group.addTask {
                try await session.fetchAccount()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw CodexAppServerError.timedOut
            }

            defer {
                group.cancelAll()
                session.terminate()
            }

            guard let fetched = try await group.next() else {
                throw CodexAppServerError.noResponse
            }
            return CodexAccountSnapshot(
                id: profile.id,
                name: profile.name,
                email: fetched.email,
                limits: fetched.limits,
                errorMessage: nil
            )
        }
    }

    func fetchRateLimits(timeout: Duration = .seconds(10)) async throws -> CodexLimitSnapshot {
        guard let limits = try await fetchAccount(profile: .defaultProfile, timeout: timeout).limits else {
            throw CodexAppServerError.noResponse
        }
        return limits
    }

    func fetchUsage(
        profile: CodexAccountProfile,
        timeout: Duration = .seconds(5)
    ) async throws -> CodexUsageSnapshot {
        if let home = profile.expandedCodexHome,
           !FileManager.default.fileExists(atPath: home) {
            throw CodexAppServerError.invalidProfileHome(home)
        }

        let session = AppServerSession(
            executableURL: executableURL,
            codexHome: profile.expandedCodexHome.map(URL.init(fileURLWithPath:))
        )

        return try await withThrowingTaskGroup(of: CodexUsageSnapshot.self) { group in
            group.addTask {
                try await session.fetchUsage()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw CodexAppServerError.timedOut
            }

            defer {
                group.cancelAll()
                session.terminate()
            }

            guard let usage = try await group.next() else {
                throw CodexAppServerError.noResponse
            }
            return usage
        }
    }

    static func decodeRateLimitResponse(_ data: Data) throws -> CodexLimitSnapshot {
        try JSONDecoder().decode(RateLimitRPCResponse.self, from: data).result.snapshot
    }

    static func decodeRateLimitResponseJSON(_ json: String) throws -> CodexLimitSnapshot {
        try decodeRateLimitResponse(Data(json.utf8))
    }

    static func decodeUsageResponse(_ data: Data) throws -> CodexUsageSnapshot {
        try JSONDecoder().decode(UsageRPCResponse.self, from: data).result.snapshot
    }

    static func decodeUsageResponseJSON(_ json: String) throws -> CodexUsageSnapshot {
        try decodeUsageResponse(Data(json.utf8))
    }
}

private final class AppServerSession: @unchecked Sendable {
    private let executableURL: URL
    private let codexHome: URL?
    private let lock = NSLock()
    private var process: Process?

    init(executableURL: URL, codexHome: URL?) {
        self.executableURL = executableURL
        self.codexHome = codexHome
    }

    func fetchAccount() async throws -> FetchedAccount {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()

        process.executableURL = executableURL
        process.arguments = ["-s", "read-only", "-a", "untrusted", "app-server"]
        if let codexHome {
            var environment = ProcessInfo.processInfo.environment
            environment["CODEX_HOME"] = codexHome.path
            environment["CODEX_SQLITE_HOME"] = codexHome.path
            process.environment = environment
        }
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        lock.withLock { self.process = process }
        defer { terminate() }

        do {
            try process.run()
        } catch {
            throw CodexAppServerError.launchFailed(error.localizedDescription)
        }

        let messages: [[String: Any]] = [
            [
                "method": "initialize",
                "id": 0,
                "params": [
                    "clientInfo": [
                        "name": "codex_limits_widget",
                        "title": "Codex Limits Widget",
                        "version": "1.0.0"
                    ]
                ]
            ],
            ["method": "initialized", "params": [:]],
            ["method": "account/read", "id": 1, "params": ["refreshToken": false]],
            ["method": "account/rateLimits/read", "id": 2, "params": NSNull()]
        ]

        for message in messages {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(0x0A)
            try input.fileHandleForWriting.write(contentsOf: data)
        }

        var accountIdentity: AccountIdentity?
        var accountReadCompleted = false
        var limits: CodexLimitSnapshot?

        do {
            for try await line in output.fileHandleForReading.bytes.lines {
                try Task.checkCancellation()
                guard let data = line.data(using: .utf8),
                      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let responseID = object["id"] as? Int,
                      responseID == 1 || responseID == 2 else {
                    continue
                }

                if let error = object["error"] as? [String: Any] {
                    let message = error["message"] as? String ?? "Unknown app-server error"
                    if responseID == 2 {
                        throw CodexAppServerError.server(message)
                    }
                    accountReadCompleted = true
                } else if responseID == 1 {
                    accountIdentity = try JSONDecoder().decode(AccountRPCResponse.self, from: data).result.account
                    accountReadCompleted = true
                } else {
                    limits = try CodexAppServerClient.decodeRateLimitResponse(data)
                }

                if let limits, accountReadCompleted {
                    return FetchedAccount(email: accountIdentity?.email, limits: limits)
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as CodexAppServerError {
            throw error
        } catch {
            throw CodexAppServerError.invalidResponse(error.localizedDescription)
        }

        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        let detail = String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        throw CodexAppServerError.server(detail?.nilIfEmpty ?? "App server closed before replying")
    }

    func fetchUsage() async throws -> CodexUsageSnapshot {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()

        process.executableURL = executableURL
        process.arguments = ["-s", "read-only", "-a", "untrusted", "app-server"]
        if let codexHome {
            var environment = ProcessInfo.processInfo.environment
            environment["CODEX_HOME"] = codexHome.path
            environment["CODEX_SQLITE_HOME"] = codexHome.path
            process.environment = environment
        }
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        lock.withLock { self.process = process }
        defer { terminate() }

        do {
            try process.run()
        } catch {
            throw CodexAppServerError.launchFailed(error.localizedDescription)
        }

        let messages: [[String: Any]] = [
            [
                "method": "initialize",
                "id": 0,
                "params": [
                    "clientInfo": [
                        "name": "codex_limits_widget",
                        "title": "Codex Limits Widget",
                        "version": "1.0.0"
                    ]
                ]
            ],
            ["method": "initialized", "params": [:]],
            ["method": "account/usage/read", "id": 1, "params": NSNull()]
        ]

        for message in messages {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(0x0A)
            try input.fileHandleForWriting.write(contentsOf: data)
        }

        do {
            for try await line in output.fileHandleForReading.bytes.lines {
                try Task.checkCancellation()
                guard let data = line.data(using: .utf8),
                      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let responseID = object["id"] as? Int,
                      responseID == 1 else {
                    continue
                }

                if let error = object["error"] as? [String: Any] {
                    throw CodexAppServerError.server(error["message"] as? String ?? "Usage is unavailable")
                }
                return try CodexAppServerClient.decodeUsageResponse(data)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as CodexAppServerError {
            throw error
        } catch {
            throw CodexAppServerError.invalidResponse(error.localizedDescription)
        }

        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        let detail = String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        throw CodexAppServerError.server(detail?.nilIfEmpty ?? "App server closed before returning usage")
    }

    func terminate() {
        let runningProcess = lock.withLock { () -> Process? in
            defer { process = nil }
            return process
        }
        if runningProcess?.isRunning == true {
            runningProcess?.terminate()
        }
    }
}

enum CodexExecutableLocator {
    static func locate(preferredPath: String? = nil) -> URL? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        var candidates: [String] = []

        if let preferredPath, !preferredPath.isEmpty {
            candidates.append((preferredPath as NSString).expandingTildeInPath)
        }

        candidates += [
            home.appendingPathComponent(".local/bin/codex").path,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/codex" }
        }

        let nvmVersions = home.appendingPathComponent(".nvm/versions/node")
        if let versions = try? fileManager.contentsOfDirectory(atPath: nvmVersions.path) {
            candidates += versions.reversed().map {
                nvmVersions.appendingPathComponent($0).appendingPathComponent("bin/codex").path
            }
        }

        guard let path = candidates.first(where: fileManager.isExecutableFile(atPath:)) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }
}

enum CodexAppServerError: LocalizedError, Equatable {
    case executableNotFound
    case launchFailed(String)
    case server(String)
    case invalidResponse(String)
    case timedOut
    case noResponse
    case invalidProfileHome(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "Codex CLI not found. Set its path in Settings."
        case .launchFailed(let detail):
            "Could not start Codex: \(detail)"
        case .server(let detail):
            "Codex app server: \(detail)"
        case .invalidResponse(let detail):
            "Could not read Codex limits: \(detail)"
        case .timedOut:
            "Codex did not respond within 10 seconds."
        case .noResponse:
            "Codex returned no limit data."
        case .invalidProfileHome(let path):
            "Account folder does not exist: \(path)"
        }
    }
}

private struct FetchedAccount: Sendable {
    let email: String?
    let limits: CodexLimitSnapshot
}

private struct AccountRPCResponse: Decodable {
    let result: AccountResult
}

private struct AccountResult: Decodable {
    let account: AccountIdentity?
}

private struct AccountIdentity: Decodable, Sendable {
    let email: String?
    let planType: String?
}

private struct UsageRPCResponse: Decodable {
    let id: Int
    let result: UsageResult
}

private struct UsageResult: Decodable {
    let dailyUsageBuckets: [CodexUsageDay]?
    let summary: CodexUsageSummary

    var snapshot: CodexUsageSnapshot {
        let buckets = Dictionary(
            (dailyUsageBuckets ?? []).map { ($0.startDate, max(0, $0.tokens)) },
            uniquingKeysWith: { _, latest in latest }
        )
        .map { CodexUsageDay(startDate: $0.key, tokens: $0.value) }
        .sorted { $0.startDate < $1.startDate }

        return CodexUsageSnapshot(fetchedAt: .now, dailyUsageBuckets: buckets, summary: summary)
    }
}

private struct RateLimitRPCResponse: Decodable {
    let id: Int
    let result: RateLimitResult
}

private struct RateLimitResult: Decodable {
    let rateLimits: RateLimitSnapshot
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?
    let rateLimitResetCredits: ResetCreditSummary?

    var snapshot: CodexLimitSnapshot {
        let buckets = rateLimitsByLimitId?.isEmpty == false
            ? rateLimitsByLimitId!.sorted(by: { $0.key < $1.key })
            : [(rateLimits.limitId ?? "codex", rateLimits)]

        var windows: [CodexLimitWindow] = []
        for (bucketID, bucket) in buckets {
            for window in [bucket.primary, bucket.secondary].compactMap({ $0 }) {
                let duration = window.windowDurationMins
                let baseTitle = Self.title(for: duration)
                let title: String
                if buckets.count > 1 {
                    let name = bucket.limitName?.nilIfEmpty ?? bucketID
                    title = "\(name) · \(baseTitle)"
                } else {
                    title = baseTitle
                }
                windows.append(
                    CodexLimitWindow(
                        id: "\(bucketID)-\(duration ?? window.usedPercent)",
                        title: title,
                        usedPercent: max(0, min(100, window.usedPercent)),
                        resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                        durationMinutes: duration
                    )
                )
            }
        }

        windows.sort { ($0.durationMinutes ?? .max) < ($1.durationMinutes ?? .max) }
        let representative = buckets.first?.value ?? rateLimits
        let now = Date.now
        let resetCredits = (rateLimitResetCredits?.credits ?? [])
            .filter { credit in
                credit.status == "available" && (credit.expirationDate.map { $0 > now } ?? true)
            }
            .sorted { lhs, rhs in
                switch (lhs.expirationDate, rhs.expirationDate) {
                case let (left?, right?): left < right
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): lhs.id < rhs.id
                }
            }
            .enumerated()
            .map { index, credit in
                CodexResetCredit(
                    id: "reset-\(credit.expiresAt ?? 0)-\(index)",
                    title: credit.title?.nilIfEmpty ?? "Full reset",
                    expiresAt: credit.expirationDate
                )
            }

        return CodexLimitSnapshot(
            fetchedAt: now,
            plan: representative.planType,
            windows: windows,
            creditBalance: representative.credits?.balance,
            resetCredits: resetCredits
        )
    }

    private static func title(for minutes: Int?) -> String {
        guard let minutes else { return "Current" }
        switch minutes {
        case 0..<60:
            return "\(minutes)-minute"
        case 60..<1_440:
            let hours = max(1, minutes / 60)
            return "\(hours)-hour"
        case 1_440..<10_080:
            return "\(minutes / 1_440)-day"
        case 10_080:
            return "Weekly"
        case 43_200...:
            return "Monthly"
        default:
            return "\(minutes / 1_440)-day"
        }
    }
}

private struct RateLimitSnapshot: Decodable {
    let limitId: String?
    let limitName: String?
    let planType: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let credits: CreditsSnapshot?
}

private struct RateLimitWindow: Decodable {
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: Int?
}

private struct CreditsSnapshot: Decodable {
    let balance: String?
}

private struct ResetCreditSummary: Decodable {
    let availableCount: Int
    let credits: [ResetCreditPayload]
}

private struct ResetCreditPayload: Decodable {
    let id: String
    let status: String
    let expiresAt: Int?
    let title: String?

    var expirationDate: Date? {
        expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
