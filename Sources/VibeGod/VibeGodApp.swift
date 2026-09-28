import SwiftUI
import AppKit

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
            } else {
                budgetSection
                Divider()
                if let today = model.today {
                    todaySection(today)
                    Divider()
                }
                commandsSection
            }
            Divider()
            Button("Refresh") { model.refresh() }
                .keyboardShortcut("r")
            Text(refreshedAt)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(minWidth: 260)
    }

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let budget = model.budget {
                Text("Month \(budget.month)")
                    .font(.headline)
                if let used = budget.usedUsd, let effective = budget.effectiveUsd {
                    let pct = effective > 0 ? used / effective * 100 : 0
                    ProgressView(value: min(pct, 100), total: 100)
                        .tint(budget.over ? Color.red : (budget.inOverageUsd != nil ? Color.orange : Color.accentColor))
                    Text(String(format: "$%.2f used of $%.2f (%.1f%%)", used, effective, pct))
                        .font(.callout)
                } else {
                    Text("\(budget.usedRequests) requests — \(formatTokens(Double(budget.usedTokens))) tokens")
                        .font(.callout)
                }
                if let over = budget.inOverageUsd {
                    Text(String(format: "In PAYG overage: $%.2f beyond the envelope", over))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let over = budget.overLimitUsd {
                    Text(String(format: "Over the ceiling by $%.2f", over))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if !budget.budget.overageAllowed {
                    Text("Overage not allowed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func todaySection(_ today: TodayReport) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Today").font(.headline)
            Text("\(today.totals.requests) requests — \(formatTokens(Double(today.totals.totalTokens))) tokens")
                .font(.callout)
            if let cost = today.totals.costUsd {
                Text(String(format: "$%.4f", cost)).font(.caption).foregroundStyle(.secondary)
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

    private var refreshedAt: String {
        "Refreshed at " + Date.now.formatted(date: .omitted, time: .standard)
    }

    private func run(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        try? process.run()
    }
}
