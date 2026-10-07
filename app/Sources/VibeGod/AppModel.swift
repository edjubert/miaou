import Foundation
import Combine
import AppKit

/// What the menu bar label shows.
enum BarMode: String, CaseIterable, Identifiable {
    case cost
    case percent
    case both
    /// Icon only: no text next to it, the icon is forced on.
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cost: return "Coût"
        case .percent: return "Pourcentage"
        case .both: return "Les deux"
        case .none: return "Aucun"
        }
    }
}

/// Menu bar label computation, pure and testable.
enum BarTitle {
    static func text(_ mode: BarMode, dashboard: DashboardReport?) -> String {
        guard let d = dashboard else { return "…" }
        let status = d.budgetStatus
        let effective = status.budget.effectiveUsd
        let used = status.usedUsd

        let pct: String? = used.flatMap { u in
            effective.flatMap { e in
                e > 0 ? String(format: "%.0f%%", u / e * 100) : nil
            }
        }
        let cost: String? = used.map { String(format: "%.2f %@", $0, d.currency) }
        let tokens = formatTokens(Double(status.usedTokens))

        let base: String
        switch mode {
        case .none:
            base = ""
        case .percent:
            base = pct ?? tokens
        case .cost:
            base = cost ?? tokens
        case .both:
            switch (cost, pct) {
            case (let c?, let p?):
                base = "\(c) (\(p))"
            case (let c?, nil):
                base = c
            case (nil, let p?):
                base = p
            case (nil, nil):
                base = tokens
            }
        }
        return base
    }
}

/// Polls vibe-god-cli and publishes the values shown in the menu bar.
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var dashboard: DashboardReport?
    @Published private(set) var lastError: String?
    @Published private(set) var lastRefresh: Date?

    private var timer: AnyCancellable?

    /// Watcher on Vibe's active-session lock directory, so a session
    /// starting or stopping refreshes the icon immediately instead of
    /// waiting for the next poll tick.
    private var lockWatcher: DispatchSourceFileSystemObject?
    private var watcherRefresh: AnyCancellable?

    var pollInterval: TimeInterval = 60

    private init() {
        refresh()
        timer = Timer.publish(every: pollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        watchSessionLocks()
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

    /// Short label in the menu bar for the selected display mode.
    func barTitle(mode: BarMode) -> String {
        BarTitle.text(mode, dashboard: dashboard)
    }

    /// Whether a Vibe session is currently running (recent lock).
    var hasLiveSessions: Bool {
        dashboard?.liveSessions.isEmpty == false
    }

    /// Watch `logs/session/active` for lock files appearing or going away.
    /// Mirrors the CLI's VIBE_HOME resolution. The directory is created by
    /// Vibe, so a failed open is retried on every refresh.
    private func watchSessionLocks() {
        guard lockWatcher == nil else { return }
        let home = ProcessInfo.processInfo.environment["VIBE_HOME"]
            ?? NSHomeDirectory() + "/.vibe"
        let dir = URL(fileURLWithPath: home)
            .appendingPathComponent("logs/session/active")
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleWatcherRefresh()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        lockWatcher = source
    }

    /// Lock changes come in bursts: one dashboard run per burst.
    private func scheduleWatcherRefresh() {
        watcherRefresh?.cancel()
        watcherRefresh = Just(())
            .delay(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
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

/// "2026-10" formatted as "Octobre 2026"; unknown keys pass through.
func monthTitle(_ ym: String) -> String {
    let parser = DateFormatter()
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.dateFormat = "yyyy-MM"
    guard let date = parser.date(from: ym) else { return ym }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "fr_FR")
    formatter.dateFormat = "MMMM yyyy"
    let raw = formatter.string(from: date)
    return raw.prefix(1).uppercased() + raw.dropFirst()
}
