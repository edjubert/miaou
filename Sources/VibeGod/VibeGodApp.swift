import SwiftUI
import AppKit
import Charts
import ServiceManagement

@main
struct VibeGodApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(AppModel.shared)
        } label: {
            BarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar label lives in its own View: observation at the App/Scene
/// level does not reliably refresh MenuBarExtra labels, a dedicated
/// observed view does.
struct BarLabel: View {
    @ObservedObject private var model = AppModel.shared
    @StateObject private var animator = ChatonAnimator()
    @AppStorage("barMode") private var barModeRaw: String = BarMode.percent.rawValue
    @AppStorage("barIcon") private var barIconRaw: String = BarIconStyle.session.rawValue

    private var style: BarIconStyle {
        BarIconStyle(rawValue: barIconRaw) ?? .session
    }

    /// While the animation is being tuned, the chaton moves whatever the
    /// session state is. Palette still follows live: color when a
    /// session runs, grayscale otherwise.
    private var animate: Bool {
        style == .chaton
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MistralIcon.image(
                style: style,
                live: model.hasLiveSessions,
                frame: animator.frame
            ))
            Text(model.barTitle(mode: BarMode(rawValue: barModeRaw) ?? .percent))
        }
        .onAppear { animator.setActive(animate) }
        .onChange(of: animate) { active in
            animator.setActive(active)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar agent: no Dock icon, no main window.
        NSApplication.shared.setActivationPolicy(.accessory)
        AppModel.shared.refresh()
    }
}

struct MenuContent: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("barMode") private var barModeRaw: String = BarMode.percent.rawValue
    @AppStorage("barIcon") private var barIconRaw: String = BarIconStyle.session.rawValue
    @AppStorage("analyticsTab") private var analyticsTab: String = "daily"
    @State private var loginError: String?

    private var barMode: BarMode {
        BarMode(rawValue: barModeRaw) ?? .percent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                Text("Is vibe-god-cli installed and up to date?")
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
                analyticsSection(dashboard)
                if !dashboard.projects.isEmpty {
                    Divider()
                    projectsSection(dashboard)
                }
                Divider()
                displaySection
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
                Divider()
                    .frame(height: 12)
                Button("Quitter") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(12)
        .frame(minWidth: 300)
        .onAppear { model.refresh() }
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Réglages").font(.headline)
            Picker("Barre de menu", selection: $barModeRaw) {
                ForEach(BarMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Picker("Icône", selection: $barIconRaw) {
                ForEach(BarIconStyle.allCases) { style in
                    Text(style.label).tag(style.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Toggle("Lancer au démarrage", isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: { enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                        loginError = nil
                    } catch {
                        loginError = error.localizedDescription
                    }
                }
            ))
            .font(.caption)
            if let loginError {
                Text(loginError)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
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
                Text(String(format: "%.2f %@ used of %.2f %@ (%.1f%%)", used, dashboard.currency, effective, dashboard.currency, pct))
                    .font(.callout)
            } else {
                Text("\(status.usedRequests) requests, \(formatTokens(Double(status.usedTokens))) tokens this month")
                    .font(.callout)
            }
            if let over = dashboard.budgetStatus.usedUsd,
               let envelope = status.budget.monthlyUsd,
               over > envelope {
                Text(status.budget.overageAllowed
                     ? String(format: "In PAYG overage: %.2f %@ beyond the envelope", over - envelope, dashboard.currency)
                     : String(format: "Over the envelope by %.2f %@", over - envelope, dashboard.currency))
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
                Text(String(format: "%.4f %@", cost, dashboard.currency)).font(.caption).foregroundStyle(.secondary)
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
            Text("Tokens consommés par jour (14 derniers jours)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Chart(days, id: \.key) { row in
                BarMark(
                    x: .value("Jour", String(row.key.suffix(5))),
                    y: .value("Tokens", row.totalTokens)
                )
                .foregroundStyle(Color.accentColor.opacity(0.85))
                .annotation(position: .top) {
                    Text(formatTokens(Double(row.totalTokens)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .frame(height: 110)
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

    private func analyticsSection(_ dashboard: DashboardReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                tabButton("Jours", tab: "daily")
                tabButton("Mois", tab: "monthly")
                tabButton("Sessions", tab: "sessions")
            }
            switch analyticsTab {
            case "monthly":
                monthlyTable(dashboard)
            case "sessions":
                sessionsTable(dashboard)
            default:
                dailyChart(dashboard)
            }
        }
    }

    private func tabButton(_ label: String, tab: String) -> some View {
        Button {
            analyticsTab = tab
        } label: {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(analyticsTab == tab ? Color.accentColor.opacity(0.25) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    private func monthlyTable(_ dashboard: DashboardReport) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(dashboard.monthly, id: \.key) { row in
                HStack {
                    Text(row.key).font(.caption)
                    Spacer()
                    Text("\(row.requests) req, \(formatTokens(Double(row.totalTokens))) tok")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let cost = row.costUsd {
                        Text(String(format: "%.2f %@", cost, dashboard.currency))
                            .font(.caption2)
                    }
                }
            }
        }
    }

    private func sessionsTable(_ dashboard: DashboardReport) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(dashboard.sessions.prefix(8)) { s in
                HStack {
                    Text(s.subagent ? "\(s.shortId)*" : s.shortId)
                        .font(.caption)
                        .monospaced()
                    Text(s.project)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(s.requests) req, \(formatTokens(Double(s.totalTokens))) tok")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func overTint(_ dashboard: DashboardReport) -> Color {
        let status = dashboard.budgetStatus
        guard let used = status.usedUsd else { return .accentColor }
        if let effective = status.budget.effectiveUsd, used > effective { return .red }
        if let envelope = status.budget.monthlyUsd, used > envelope { return .orange }
        return .accentColor
    }

}
