import SwiftUI
import AppKit
import Charts

@main
struct VibeGodApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(appDelegate.model)
        } label: {
            Image(systemName: "bolt.horizontal.circle")
                .symbolRenderingMode(.hierarchical)
            Text(appDelegate.model.barTitle)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar agent: no Dock icon, no main window.
        NSApplication.shared.setActivationPolicy(.accessory)
        model.refresh()
    }
}

struct MenuContent: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                Text("Is vibe-god-cli installed and in PATH?")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let dashboard = model.dashboard {
                budgetSection(dashboard)
                Divider()
                todaySection(dashboard)
                if !dashboard.liveSessions.isEmpty {
                    Divider()
                    liveSection(dashboard)
                }
                Divider()
                dailyChart(dashboard)
                if !dashboard.projects.isEmpty {
                    Divider()
                    projectsSection(dashboard)
                }
                Divider()
                commandsSection
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            Divider()
            HStack {
                Button("Refresh") { model.refresh() }
                    .keyboardShortcut("r")
                Spacer()
                if let refreshed = model.lastRefresh {
                    Text(refreshed.formatted(date: .omitted, time: .standard))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(minWidth: 300)
        .onAppear { model.refresh() }
    }

    private func budgetSection(_ dashboard: DashboardReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let status = dashboard.budgetStatus
            Text("Month \(status.month)")
                .font(.headline)
            if let used = status.usedUsd, let effective = status.budget.effectiveUsd, effective > 0 {
                let pct = used / effective * 100
                ProgressView(value: min(pct, 100), total: 100)
                    .tint(overTint(dashboard))
                Text(String(format: "%@%.2f used of %@%.2f (%.1f%%)", dashboard.currency, used, dashboard.currency, effective, pct))
                    .font(.callout)
            } else {
                Text("\(status.usedRequests) requests, \(formatTokens(Double(status.usedTokens))) tokens this month")
                    .font(.callout)
            }
            if let over = dashboard.budgetStatus.usedUsd,
               let envelope = status.budget.monthlyUsd,
               over > envelope {
                Text(status.budget.overageAllowed
                     ? String(format: "In PAYG overage: %@%.2f beyond the envelope", dashboard.currency, over - envelope)
                     : String(format: "Over the envelope by %@%.2f", dashboard.currency, over - envelope))
                    .font(.caption)
                    .foregroundStyle(status.budget.overageAllowed ? .orange : .red)
            }
        }
    }

    private func todaySection(_ dashboard: DashboardReport) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Today").font(.headline)
            let t = dashboard.todayTotals
            Text("\(t.requests) requests, \(formatTokens(Double(t.totalTokens))) tokens")
                .font(.callout)
            if let cost = t.costUsd {
                Text(String(format: "%@%.4f", dashboard.currency, cost)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func liveSection(_ dashboard: DashboardReport) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
            Text("Active session")
                .font(.callout)
            Spacer()
            Text(dashboard.liveSessions[0].id.prefix(8))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func dailyChart(_ dashboard: DashboardReport) -> some View {
        let days = dashboard.daily.suffix(14)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Daily usage (tokens, last 14 days)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Chart(days, id: \.key) { row in
                BarMark(
                    x: .value("Day", String(row.key.suffix(5))),
                    y: .value("Tokens", row.totalTokens)
                )
                .foregroundStyle(Color.accentColor.opacity(0.85))
            }
            .chartXAxis(.hidden)
            .frame(height: 70)
        }
    }

    private func projectsSection(_ dashboard: DashboardReport) -> some View {
        let total = dashboard.projects.map { $0.totalTokens }.reduce(0, +)
        let top = dashboard.projects.sorted { $0.totalTokens > $1.totalTokens }.prefix(5)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Projects (share of month tokens)").font(.headline)
            ForEach(Array(top), id: \.key) { row in
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(row.key).font(.caption)
                        Spacer()
                        let share = total > 0 ? Double(row.totalTokens) / Double(total) * 100 : 0
                        Text(String(format: "%.0f%%, %@ tok", share, formatTokens(Double(row.totalTokens))))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(row.totalTokens), total: Double(max(total, 1)))
                        .frame(height: 4)
                }
            }
        }
    }

    private var commandsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("vibe-god-cli").font(.caption).foregroundStyle(.secondary)
            Button("Daily breakdown") { run("vibe-god-cli daily") }
            Button("Monthly breakdown") { run("vibe-god-cli monthly") }
            Button("Sessions") { run("vibe-god-cli sessions") }
        }
    }

    private func overTint(_ dashboard: DashboardReport) -> Color {
        let status = dashboard.budgetStatus
        guard let used = status.usedUsd else { return .accentColor }
        if let effective = status.budget.effectiveUsd, used > effective { return .red }
        if let envelope = status.budget.monthlyUsd, used > envelope { return .orange }
        return .accentColor
    }

    private func run(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        try? process.run()
    }
}
