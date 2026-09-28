import Foundation
import AppKit

// Decodable mirror of `vibe-god-cli dashboard` JSON output.
// Run: /usr/bin/env vibe-god-cli dashboard --json

struct TotalsReport: Codable, Equatable {
    let requests: Int
    let inputTokens: Int
    let outputTokens: Int
    let cachedInputTokens: Int
    let totalTokens: Int
    let costUsd: Double?
}

struct PeriodRow: Codable, Equatable {
    let key: String
    let sessions: Int
    let requests: Int
    let inputTokens: Int
    let outputTokens: Int
    let cachedInputTokens: Int
    let totalTokens: Int
    let costUsd: Double?
}

struct SessionRow: Codable, Equatable, Identifiable {
    let sessionId: String
    let shortId: String
    let project: String
    let title: String?
    let subagent: Bool
    let startedMs: Int?
    let requests: Int
    let inputTokens: Int
    let outputTokens: Int
    let cachedInputTokens: Int
    let totalTokens: Int
    let costUsd: Double?

    var id: String { sessionId }
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

struct ActiveSessionReport: Codable, Equatable {
    let id: String
    let ageMs: Int

    /// Vibe leaves stale locks behind; only recent ones mean a live session.
    var isLive: Bool { ageMs < 5 * 60 * 1000 }
}

struct DashboardReport: Codable, Equatable {
    let generatedAtMs: Int
    let today: String
    let currentMonth: String
    let plan: PlanReport?
    let totals: TotalsReport
    let todayTotals: TotalsReport
    let monthToDate: TotalsReport
    let budgetStatus: BudgetStatusReport
    let daily: [PeriodRow]
    let monthly: [PeriodRow]
    let projects: [PeriodRow]
    let sessions: [SessionRow]
    let active: [ActiveSessionReport]

    var liveSessions: [ActiveSessionReport] {
        active.filter(\.isLive)
    }
}

enum VibeGodError: Error {
    case processFailed(exitCode: Int32)
    case badJSON(String)
}

/// Runs the vibe-god-cli binary and decodes its JSON output.
enum VibeGodCLI {
    /// Candidate locations, tried in order. GUI apps inherit a minimal PATH
    /// (no ~/.cargo/bin), so an explicit lookup is required.
    private static var candidates: [String] {
        [
            NSHomeDirectory() + "/.cargo/bin/vibe-god-cli",
            "/opt/homebrew/bin/vibe-god-cli",
            "/usr/local/bin/vibe-god-cli",
        ]
    }

    static func dashboard() throws -> DashboardReport {
        let process = Process()
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["dashboard", "--json"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["vibe-god-cli", "dashboard", "--json"]
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // keep the UI quiet on CLI diagnostics
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw VibeGodError.processFailed(exitCode: process.terminationStatus)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(DashboardReport.self, from: data)
        } catch {
            throw VibeGodError.badJSON(String(data: data, encoding: .utf8) ?? "<no data>")
        }
    }
}
