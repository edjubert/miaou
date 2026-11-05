import SwiftUI
import ServiceManagement

/// The main window: graphs (daily chart, monthly, per-session) and the
/// settings. The menu bar panel keeps the budget, today and the active
/// sessions.
struct MainWindow: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("barMode") private var barModeRaw: String = BarMode.percent.rawValue
    @AppStorage("barIcon") private var barIconRaw: String = BarIconStyle.logo.rawValue
    @AppStorage("chatonColor") private var chatonColorRaw: String = ChatonColorMode.session.rawValue
    @AppStorage("showIcon") private var showIcon: Bool = true
    @AppStorage("analyticsTab") private var analyticsTab: String = "daily"
    @AppStorage("language") private var languageRaw: String = "system"
    @State private var loginError: String?

    private var barMode: BarMode {
        BarMode(rawValue: barModeRaw) ?? .percent
    }

    /// App version from the bundle plist, stamped by `make app` from the
    /// CLI's Cargo.toml version. "dev" when run via `swift run`.
    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                Text(L10n.t("installed.question"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let dashboard = model.dashboard {
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
                Button(L10n.t("refresh.button")) { model.refresh() }
                    .keyboardShortcut("r")
                if let refreshed = model.lastRefresh {
                    Text(refreshed.formatted(date: .omitted, time: .standard))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(L10n.t("version.display", appVersion))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(minWidth: 360)
        .onAppear { model.refresh() }
        .onChange(of: languageRaw) { _ in model.publishWidget() }
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("settings.headline")).font(.headline)
            Picker(L10n.t("bar.picker"), selection: Binding(
                get: { barModeRaw },
                set: { raw in
                    barModeRaw = raw
                    // A bar without text needs its icon: turn it on.
                    if BarMode(rawValue: raw) == BarMode.none { showIcon = true }
                }
            )) {
                ForEach(BarMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // Rebuild on language change: segmented pickers keep their
            // initial segment titles otherwise, leaving stale labels.
            .id(languageRaw)
            Toggle(L10n.t("icon.toggle"), isOn: $showIcon)
                .font(.caption)
                .disabled(barMode == .none)
            Toggle(L10n.t("login.toggle"), isOn: Binding(
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
            Picker(L10n.t("settings.language"), selection: $languageRaw) {
                Text(L10n.t("language.system")).tag("system")
                Text(L10n.t("language.french")).tag("fr")
                Text(L10n.t("language.english")).tag("en")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .font(.caption)
            if let loginError {
                Text(loginError)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            Text(L10n.t("icon.headline")).font(.headline)
            Picker(L10n.t("icon.headline"), selection: $barIconRaw) {
                ForEach(BarIconStyle.allCases) { style in
                    Text(style.label).tag(style.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .id(languageRaw)
            Picker(L10n.t("colorMode.picker"), selection: $chatonColorRaw) {
                ForEach(ChatonColorMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .id(languageRaw)
        }
    }

    private func dailyChart(_ dashboard: DashboardReport) -> some View {
        DailyChartView(days: dashboard.daily.suffix(14))
    }

    private func projectsSection(_ dashboard: DashboardReport) -> some View {
        let total = dashboard.projects.map { $0.totalTokens }.reduce(0, +)
        let top = dashboard.projects.sorted { $0.totalTokens > $1.totalTokens }.prefix(5)
        return VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("projects.headline")).font(.headline)
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
                tabButton(L10n.t("tab.daily"), tab: "daily")
                tabButton(L10n.t("tab.monthly"), tab: "monthly")
                tabButton(L10n.t("tab.sessions"), tab: "sessions")
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
                    Text(L10n.t("row.req_tok", row.requests, formatTokens(Double(row.totalTokens))))
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
                SessionFold(row: s, currency: dashboard.currency)
            }
        }
    }
}
