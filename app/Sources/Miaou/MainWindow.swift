import SwiftUI
import AppKit
import ServiceManagement

/// Sidebar sections of the main window.
enum MainSection: String, CaseIterable, Identifiable {
    case graphs, projects, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .graphs: return L10n.t("section.graphs")
        case .projects: return L10n.t("section.projects")
        case .settings: return L10n.t("settings.headline")
        }
    }
    var symbol: String {
        switch self {
        case .graphs: return "chart.bar"
        case .projects: return "folder"
        case .settings: return "slider.horizontal.3"
        }
    }
}

/// Liquid glass card on macOS 26+, material fallback before (same pattern as
/// kapitsa's NativeGlassCard).
struct GlassCard: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

/// Brings the main window forward after `openWindow(id: "main")`: opening an
/// existing SwiftUI scene need not make its NSWindow key while the menu bar
/// panel has focus (same pattern as kapitsa's DesktopWindowFocus).
enum MainWindowFocus {
    static let identifier = NSUserInterfaceItemIdentifier("miaou-main")

    @MainActor static func activate() {
        DispatchQueue.main.async {
            NSApplication.shared.windows.first { $0.identifier == identifier }?.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}

/// Tags the hosting NSWindow with `MainWindowFocus.identifier`.
struct MainWindowMarker: NSViewRepresentable {
    final class Anchor: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.identifier = MainWindowFocus.identifier
        }
    }
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ nsView: Anchor, context: Context) {}
}

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

    @State private var section: MainSection? = .graphs

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                ForEach(MainSection.allCases, id: \.self) { item in
                    Button {
                        section = item
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .tag(Optional(item))
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 6) {
                    if let refreshed = model.lastRefresh {
                        Text(refreshed.formatted(date: .omitted, time: .standard))
                    }
                    Spacer()
                    Text(L10n.t("version.display", appVersion))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(16)
            }
        } detail: {
            VStack(spacing: 0) {
                if let error = model.lastError {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.red)
                        Text(L10n.t("installed.question"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.orange.opacity(0.12))
                }
                if let dashboard = model.dashboard {
                    content(dashboard)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle((section ?? .graphs).title)
            .toolbar {
                ToolbarItemGroup {
                    Button(L10n.t("refresh.button"), systemImage: "arrow.clockwise") {
                        model.refresh()
                    }
                    .help(L10n.t("refresh.button"))
                }
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .background(MainWindowMarker())
        .onAppear { model.refresh() }
        .onChange(of: languageRaw) { _ in model.publishWidget() }
    }

    @ViewBuilder private func content(_ dashboard: DashboardReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                switch section ?? .graphs {
                case .graphs:
                    analyticsSection(dashboard)
                        .modifier(GlassCard())
                        .padding(16)
                case .projects:
                    if dashboard.projects.isEmpty {
                        Text(L10n.t("projects.headline")).font(.headline)
                    } else {
                        projectsSection(dashboard)
                            .modifier(GlassCard())
                            .padding(16)
                    }
                case .settings:
                    displaySection
                        .modifier(GlassCard())
                        .padding(16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
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
