import Foundation
import Combine
import AppKit

/// Polls vibe-god-cli and publishes the values shown in the menu bar.
final class AppModel: ObservableObject {
    @Published private(set) var dashboard: DashboardReport?
    @Published private(set) var lastError: String?
    @Published private(set) var lastRefresh: Date?

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
            let dashboard = try VibeGodCLI.dashboard()
            DispatchQueue.main.async {
                self.dashboard = dashboard
                self.lastError = nil
                self.lastRefresh = Date()
            }
        } catch {
            DispatchQueue.main.async {
                self.lastError = Self.describe(error)
            }
        }
    }

    /// Short label in the menu bar: envelope percentage when cost is
    /// available, month tokens otherwise. Green dot suffix while a session
    /// is live.
    var barTitle: String {
        let base: String
        if let dashboard {
            let status = dashboard.budgetStatus
            if let used = status.usedUsd, let effective = status.budget.effectiveUsd, effective > 0 {
                base = String(format: "%.0f%%", used / effective * 100)
            } else {
                base = formatTokens(Double(status.usedTokens))
            }
        } else {
            base = "…"
        }
        return dashboard?.liveSessions.isEmpty == false ? base + " •" : base
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
