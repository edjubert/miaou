import Foundation
import AppKit

// Decodable mirror of `miaou dashboard` JSON output.
// Run: /usr/bin/env miaou dashboard --json

struct TotalsReport: Codable, Equatable {
    let requests: Int
    let inputTokens: Int
    let outputTokens: Int
    let cachedInputTokens: Int
    let totalTokens: Int
    let costUsd: Double?
}

struct PeriodRow: Codable, Equatable, Identifiable {
    let key: String
    var id: String { key }
    let sessions: Int
    let requests: Int
    let inputTokens: Int
    let outputTokens: Int
    let cachedInputTokens: Int
    let totalTokens: Int
    let costUsd: Double?
    /// Git remote URL and worktree paths for project rows; nil for period
    /// rows. Optional + default so old JSON stays readable.
    var remote: String? = nil
    var worktrees: [String]? = nil
}

struct SessionRow: Codable, Equatable, Identifiable {
    let sessionId: String
    let shortId: String
    let project: String
    let title: String?
    /// How the title was set: "auto" (generated) or "manual" (/rename).
    /// Nil when the CLI is too old to report it. `var` + default so the
    /// synthesized Codable still decodes it and old JSON stays readable.
    var titleSource: String? = nil
    /// True while the session's OS lock is held (the session is running).
    /// Nil when the CLI is too old to report it.
    var active: Bool? = nil
    let subagent: Bool
    let startedMs: Int?
    let requests: Int
    let inputTokens: Int
    let outputTokens: Int
    let cachedInputTokens: Int
    let totalTokens: Int
    let costUsd: Double?

    var id: String { sessionId }

    var isActive: Bool { active ?? false }
}

struct PlanReport: Codable, Equatable {
    let planType: String?
    let planName: String?
    let organizationKind: String?
}

struct BudgetReport: Codable, Equatable {
    let monthlyUsd: Double?
    let overageUsd: Double?
    let overageAllowed: Bool
    let monthlyTokens: Int?

    var effectiveUsd: Double? {
        monthlyUsd.map { overageAllowed ? $0 + (overageUsd ?? 0) : $0 }
    }
}

struct BudgetStatusReport: Codable, Equatable {
    let month: String
    let usedUsd: Double?
    let usedTokens: Int
    let usedRequests: Int
    let budget: BudgetReport
}

/// Console observation the month cost is anchored on, when the CLI's
/// calibration ledger holds one for the current month.
struct AnchorReport: Codable, Equatable {
    /// Observation time (epoch ms, UTC).
    let atMs: Int
    /// Console cost at that time, in the display currency.
    let cost: Double
    /// Cost of the local tokens consumed since the anchor, when an
    /// estimate was available.
    let deltaUsd: Double?
}

struct ActiveSessionReport: Codable, Equatable {
    let id: String
    /// Diagnostic only: an open session does not need to touch its lock.
    let ageMs: Int
    /// Session metadata, when the CLI reports it. `var` + default so the
    /// synthesized Codable still decodes them and old JSON stays readable.
    var title: String? = nil
    var titleSource: String? = nil
}

/// Vibe's active model, resolved from `config.toml` by the CLI.
struct ModelRefReport: Codable, Equatable {
    let name: String
    let alias: String?

    /// "Le Chonk" is the alias of mistral-large-4; a versioned runtime
    /// name (`mistral-large-4-0-3`) resolves to the same base. Only
    /// numeric version tails count, like the CLI's base-name matching.
    var isChonk: Bool {
        if alias == "Le Chonk" || name == "mistral-large-4" { return true }
        let prefix = "mistral-large-4-"
        guard name.hasPrefix(prefix) else { return false }
        return name.dropFirst(prefix.count)
            .split(separator: "-")
            .allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }
}

struct DashboardReport: Codable, Equatable {
    let generatedAtMs: Int
    let today: String
    let currentMonth: String
    /// Vibe's active model, when the CLI can resolve it.
    let activeModel: ModelRefReport?
    /// Cost display symbol, from the CLI's [display] currency setting.
    let currency: String
    let plan: PlanReport?
    let totals: TotalsReport
    let todayTotals: TotalsReport
    let monthToDate: TotalsReport
    let budgetStatus: BudgetStatusReport
    /// Console anchor applied to the month cost (from the CLI's
    /// calibration ledger), nil when the month is valued per session.
    let anchor: AnchorReport?
    let daily: [PeriodRow]
    let monthly: [PeriodRow]
    let projects: [PeriodRow]
    let sessions: [SessionRow]
    var active: [ActiveSessionReport]

    var liveSessions: [ActiveSessionReport] {
        // The CLI checks the OS lock; orphaned files are already excluded.
        active
    }
}

enum MiaouError: Error {
    case processFailed(exitCode: Int32)
    case badJSON(String)
    case invalidAnchorCost
}

/// Runs the miaou binary and decodes its JSON output.
enum MiaouCLI {
    /// Candidate locations, tried in order. The preferred one is the copy
    /// embedded in the .app bundle by `make app` as `miaou-cli` (a name that
    /// does not collide with the app executable on case-insensitive APFS),
    /// which makes the installed app self-contained. GUI apps inherit a
    /// minimal PATH (no ~/.cargo/bin), so explicit lookups are required for
    /// the fallbacks.
    private static var candidates: [String] {
        [
            Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/miaou-cli").path,
            NSHomeDirectory() + "/.cargo/bin/miaou",
            "/opt/homebrew/bin/miaou",
            "/usr/local/bin/miaou",
        ]
    }

    private static func run(arguments: [String], environment: [String: String]? = nil) throws -> Data {
        let process = Process()
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["miaou"] + arguments
        }
        // On macOS, assigning nil clears the child's environment rather
        // than inheriting it. Keep the default unless explicitly overridden.
        if let environment {
            process.environment = environment
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice // keep the UI quiet on CLI diagnostics
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw MiaouError.processFailed(exitCode: process.terminationStatus)
        }
        return data
    }

    static func dashboard() throws -> DashboardReport {
        let data = try run(arguments: ["dashboard", "--json"])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(DashboardReport.self, from: data)
        } catch {
            throw MiaouError.badJSON(String(data: data, encoding: .utf8) ?? "<no data>")
        }
    }

    /// Records the Console month total in the display currency at the
    /// current time. An environment override allows isolated ledger runs.
    static func addAnchor(cost: Double, environment: [String: String]? = nil) throws {
        guard cost.isFinite, cost >= 0 else { throw MiaouError.invalidAnchorCost }
        _ = try run(
            arguments: ["calibrate", "add", "--cost", String(cost)],
            environment: environment
        )
    }
}
