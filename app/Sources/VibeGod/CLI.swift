import Foundation

// Decodable mirrors of vibe-god-cli JSON output.
// Run: /usr/bin/env vibe-god-cli budget --json / today --json

struct BudgetReport: Codable, Equatable {
    struct Budget: Codable, Equatable {
        let monthlyUsd: Double?
        let overageUsd: Double?
        let overageAllowed: Bool
        let monthlyTokens: Int?
    }

    let month: String
    let usedUsd: Double?
    let usedTokens: Int
    let usedRequests: Int
    let budget: Budget
    let effectiveUsd: Double?
    let remainingUsd: Double?
    let inOverageUsd: Double?
    let overLimitUsd: Double?
    let over: Bool
}

struct TodayReport: Codable, Equatable {
    struct Totals: Codable, Equatable {
        let requests: Int
        let inputTokens: Int
        let outputTokens: Int
        let cachedInputTokens: Int
        let totalTokens: Int
        let costUsd: Double?
    }

    let date: String
    let totals: Totals
}

enum VibeGodError: Error {
    case processFailed(exitCode: Int32)
    case badJSON(String)
}

/// Runs the vibe-god-cli binary and decodes its JSON output.
enum VibeGodCLI {
    static func json<T: Decodable>(_ type: T.Type, _ arguments: [String]) throws -> T {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["vibe-god-cli"] + arguments + ["--json"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // keep the UI quiet on CLI diagnostics
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw VibeGodError.processFailed(exitCode: process.terminationStatus)
        }
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(type, from: data)
        } catch {
            throw VibeGodError.badJSON(String(data: data, encoding: .utf8) ?? "<no data>")
        }
    }
}
