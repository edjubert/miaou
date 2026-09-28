import Foundation
import Combine
import AppKit

/// Polls vibe-god-cli and publishes the values shown in the menu bar.
final class AppModel: ObservableObject {
    @Published private(set) var budget: BudgetReport?
    @Published private(set) var today: TodayReport?
    @Published private(set) var lastError: String?

    private var timer: AnyCancellable?

    var pollInterval: TimeInterval = 60

    init() {
        refresh()
        timer = Timer.publish(every: pollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        do {
            let budget = try VibeGodCLI.json(BudgetReport.self, ["budget"])
            let today = try VibeGodCLI.json(TodayReport.self, ["today"])
            DispatchQueue.main.async {
                self.budget = budget
                self.today = today
                self.lastError = nil
            }
        } catch {
            DispatchQueue.main.async {
                self.lastError = Self.describe(error)
            }
        }
    }

    /// Short label in the menu bar: envelope percentage when cost is
    /// available, month tokens otherwise.
    var barTitle: String {
        guard let budget else { return "…" }
        if let used = budget.usedUsd, let effective = budget.effectiveUsd, effective > 0 {
            let pct = used / effective * 100
            return String(format: "%.0f%%", pct)
        }
        return formatTokens(Double(budget.usedTokens))
    }

    var statusColor: String {
        guard let budget else { return "secondary" }
        if budget.over { return "red" }
        if budget.inOverageUsd != nil { return "orange" }
        return "primary"
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case VibeGodError.processFailed(let code):
            return "vibe-god-cli exited with \(code)"
        case VibeGodError.badJSON:
            return "vibe-god-cli returned unexpected JSON"
        default:
            return error.localizedDescription
        }
    }
}

func formatTokens(_ value: Double) -> String {
    let units: [(Double, String)] = [(1_000_000_000, "B"), (1_000_000, "M"), (1_000, "k")]
    for (divisor, suffix) in units where value >= divisor {
        return String(format: "%.1f%@", value / divisor, suffix)
    }
    return String(format: "%.0f", value)
}
