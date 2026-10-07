import SwiftUI
import AppKit
import Charts
import ServiceManagement

@main
struct MiaouApp: App {
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
    @AppStorage("barIcon") private var barIconRaw: String = BarIconStyle.logo.rawValue
    @AppStorage("chatonColor") private var chatonColorRaw: String = ChatonColorMode.session.rawValue
    @AppStorage("showIcon") private var showIcon: Bool = true

    private var style: BarIconStyle {
        BarIconStyle(rawValue: barIconRaw) ?? .logo
    }

    private var colorMode: ChatonColorMode {
        ChatonColorMode(rawValue: chatonColorRaw) ?? .session
    }

    private var mode: BarMode {
        BarMode(rawValue: barModeRaw) ?? .percent
    }

    /// A bar without text always keeps its icon.
    private var showsIcon: Bool {
        showIcon || mode == .none
    }

    /// The chaton loops while a session is live, and rests on its
    /// sleeping pose otherwise.
    private var animate: Bool {
        style == .chaton && model.hasLiveSessions
    }

    var body: some View {
        HStack(spacing: 4) {
            if showsIcon {
                Image(nsImage: MistralIcon.image(
                    style: style,
                    live: model.hasLiveSessions,
                    frame: animator.frame,
                    colorMode: colorMode
                ))
            }
            if mode != .none {
                Text(model.barTitle(mode: mode))
            }
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

/// The petit chat as a full-width banner at the top of the menu window,
/// looping like the Vibe CLI banner it comes from, resting a while on
/// its sleeping pose each time the cycle reaches it.
struct ChatonBanner: View {
    @StateObject private var animator = ChatonAnimator(restsInLoop: true)
    @AppStorage("chatonColor") private var chatonColorRaw: String = ChatonColorMode.session.rawValue

    private var colorMode: ChatonColorMode {
        ChatonColorMode(rawValue: chatonColorRaw) ?? .session
    }

    // Fixed height: a resizable image with aspectRatio fit has no
    // intrinsic size, so a height-starved VStack squeezes it to zero
    // and the banner vanishes.
    static let height: CGFloat = 132

    var body: some View {
        Image(nsImage: MistralIcon.bannerImage(frame: animator.frame, colorMode: colorMode))
            .resizable()
            .aspectRatio(23.0 / 11.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .onAppear { animator.setActive(true) }
            .onDisappear { animator.setActive(false) }
    }
}

// Localized labels for the enums living in MistralLogo.swift: that file
// is also compiled standalone by `make icon`, so it must not reference
// Bundle.module (see L10n.swift).
extension BarIconStyle {
    var label: String {
        switch self {
        case .logo: return L10n.t("iconStyle.logo")
        case .chaton: return L10n.t("iconStyle.chaton")
        }
    }
}

extension ChatonColorMode {
    var label: String {
        switch self {
        case .session: return L10n.t("colorMode.session")
        case .color: return L10n.t("colorMode.color")
        case .grayscale: return L10n.t("colorMode.grayscale")
        }
    }
}

struct MenuContent: View {
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
            ChatonBanner()
            if let error = model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                Text(L10n.t("installed.question"))
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
                Divider()
                    .frame(height: 12)
                Button(L10n.t("quit.button")) {
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

    private func budgetSection(_ dashboard: DashboardReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let status = dashboard.budgetStatus
            Text(monthTitle(status.month))
                .font(.headline)
            if let used = status.usedUsd, let effective = status.budget.effectiveUsd, effective > 0 {
                let pct = used / effective * 100
                ProgressView(value: min(pct, 100), total: 100)
                    .tint(overTint(dashboard))
                Text(L10n.t("budget.used_of", used, dashboard.currency, effective, dashboard.currency, pct))
                    .font(.callout)
                if let forecast = quotaForecast(dashboard) {
                    // Two single-line Texts, not one multiline Text: the
                    // menu window clips a Text whose height grows mid-layout.
                    Text(forecast.pace)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(forecast.outcome)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(L10n.t("budget.requests_tokens_month", status.usedRequests, formatTokens(Double(status.usedTokens))))
                    .font(.callout)
            }
            if let over = dashboard.budgetStatus.usedUsd,
               let envelope = status.budget.monthlyUsd,
               over > envelope {
                Text(status.budget.overageAllowed
                     ? L10n.t("budget.payg", over - envelope, dashboard.currency)
                     : L10n.t("budget.over", over - envelope, dashboard.currency))
                    .font(.caption)
                    .foregroundStyle(status.budget.overageAllowed ? .orange : .red)
            }
        }
    }

    /// Estimated days until the monthly quota is exhausted, at the average
    /// daily pace observed since the start of the month. Returns the pace
    /// and outcome lines to render as separate Texts. Nil when there is
    /// no usable cost data or the quota is already spent.
    private func quotaForecast(_ dashboard: DashboardReport) -> (pace: String, outcome: String)? {
        let status = dashboard.budgetStatus
        guard let used = status.usedUsd,
              let effective = status.budget.effectiveUsd,
              effective > 0, used > 0, used < effective else { return nil }

        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let today = parser.date(from: dashboard.today) else { return nil }

        let calendar = Calendar.current
        guard let dayOfMonth = calendar.ordinality(of: .day, in: .month, for: today),
              let lastDay = calendar.range(of: .day, in: .month, for: today)?.last else { return nil }
        let avgDaily = used / Double(max(dayOfMonth, 1))
        let days = Int(ceil((effective - used) / avgDaily))
        let pace = L10n.t("forecast.pace", avgDaily, dashboard.currency)

        if dayOfMonth + days > lastDay {
            return (pace: pace, outcome: L10n.t("forecast.holds"))
        }
        guard let hit = calendar.date(byAdding: .day, value: days, to: today) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return (pace: pace, outcome: L10n.t("forecast.hit", days, formatter.string(from: hit)))
    }

    private func todaySection(_ dashboard: DashboardReport) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.t("today.headline")).font(.headline)
            let t = dashboard.todayTotals
            Text(L10n.t("today.requests_tokens", t.requests, formatTokens(Double(t.totalTokens))))
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
            Text(L10n.t("live.active"))
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
            Text(L10n.t("chart.daily.title"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Chart(days, id: \.key) { row in
                BarMark(
                    x: .value(L10n.t("chart.axis.day"), String(row.key.suffix(5))),
                    y: .value(L10n.t("chart.axis.tokens"), row.totalTokens)
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
                HStack {
                    Text(s.subagent ? "\(s.shortId)*" : s.shortId)
                        .font(.caption)
                        .monospaced()
                    Text(s.project)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text(L10n.t("row.req_tok", s.requests, formatTokens(Double(s.totalTokens))))
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
