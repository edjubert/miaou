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
/// kapitsa's NativeGlassCard). `.clear` is the most transparent glass variant
/// (Glass has no opacity knob in the macOS 26 SDK), so the card lets the
/// wallpaper through; before macOS 26 the thinnest material does the same.
struct GlassCard: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.clear, in: RoundedRectangle(cornerRadius: 18))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

/// Big stat card at the top of a section, like kapitsa's MetricCard.
struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.system(.title, design: .rounded).weight(.semibold)).monospacedDigit()
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(GlassCard())
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

/// The main window: native sidebar + detail with graphs (metric cards, chart,
/// tables) and settings. The menu bar panel keeps the budget, today and the
/// active sessions.
struct MainWindow: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("barMode") private var barModeRaw: String = BarMode.percent.rawValue
    @AppStorage("barIcon") private var barIconRaw: String = BarIconStyle.logo.rawValue
    @AppStorage("chatonColor") private var chatonColorRaw: String = ChatonColorMode.session.rawValue
    @AppStorage("barAnimation") private var barAnimationRaw: String = ChatonAnimationMode.session.rawValue
    @AppStorage("showIcon") private var showIcon: Bool = true
    @AppStorage("showInDock") private var showInDock: Bool = true
    @AppStorage("desktopPetEnabled") private var desktopPetEnabled = false
    // Keep the stored key so the previous color preference survives upgrades.
    @AppStorage("desktopPetColorDuringSession") private var desktopPetColorDuringMovement = true
    // Store transparency to preserve the existing appearance; the slider shows glass intensity.
    @AppStorage("desktopPetGlassTransparency") private var desktopPetGlassTransparency = 0.0
    @AppStorage("analyticsTab") private var analyticsTab: String = "daily"
    @AppStorage("language") private var languageRaw: String = "system"
    @State private var loginError: String?
    @State private var section: MainSection? = .graphs
    @State private var sessionSelection: String?

    private var barMode: BarMode {
        BarMode(rawValue: barModeRaw) ?? .percent
    }

    /// App version from the bundle plist, stamped by `make app` from the
    /// CLI's Cargo.toml version. "dev" when run via `swift run`.
    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }

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
        switch section ?? .graphs {
        case .graphs:
            graphsSection(dashboard)
        case .projects:
            projectsSection(dashboard)
        case .settings:
            // A Form scrolls itself.
            settingsForm
                .padding(20)
        }
    }

    // MARK: - Graphs

    private func graphsSection(_ dashboard: DashboardReport) -> some View {
        // No ScrollView around the tables: a Table needs a bounded height to
        // render rows and scrolls natively inside the detail pane.
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                MetricCard(
                    title: L10n.t("metric.month"),
                    value: dashboard.budgetStatus.usedUsd.map { String(format: "%.2f %@", $0, dashboard.currency) } ?? "—",
                    subtitle: dashboard.budgetStatus.budget.effectiveUsd.map {
                        L10n.t("metric.month.sub", $0, dashboard.currency)
                    } ?? L10n.t("metric.month.sub.none"),
                    symbol: "eurosign.circle")
                MetricCard(
                    title: L10n.t("today.headline"),
                    value: formatTokens(Double(dashboard.todayTotals.totalTokens)),
                    subtitle: L10n.t("metric.today.sub", dashboard.todayTotals.requests),
                    symbol: "bolt.circle")
                MetricCard(
                    title: L10n.t("metric.active"),
                    value: "\(dashboard.liveSessions.count)",
                    subtitle: L10n.t("metric.active.sub"),
                    symbol: "circle.fill")
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Picker("", selection: $analyticsTab) {
                Text(L10n.t("tab.daily")).tag("daily")
                Text(L10n.t("tab.monthly")).tag("monthly")
                Text(L10n.t("tab.sessions")).tag("sessions")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 24)

            Group {
                switch analyticsTab {
                case "monthly":
                    monthlyTable(dashboard)
                case "sessions":
                    sessionsTable(dashboard)
                default:
                    ScrollView {
                        DailyChartView(days: dashboard.daily.suffix(14), height: 260)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func monthlyTable(_ dashboard: DashboardReport) -> some View {
        Table(dashboard.monthly) {
            TableColumn(L10n.t("col.month")) { row in Text(row.key) }
            TableColumn(L10n.t("col.requests")) { row in Text("\(row.requests)") }
            TableColumn(L10n.t("col.tokens")) { row in Text(formatTokens(Double(row.totalTokens))).monospacedDigit() }
            TableColumn(L10n.t("col.cost")) { row in
                if let cost = row.costUsd {
                    Text(String(format: "%.2f %@", cost, dashboard.currency)).monospacedDigit()
                }
            }
        }
        .padding(8)
    }

    private func sessionsTable(_ dashboard: DashboardReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Table(dashboard.sessions, selection: $sessionSelection) {
                TableColumn(L10n.t("col.session")) { s in
                    Text(s.subagent ? "\(s.shortId)*" : s.shortId).monospaced()
                }.width(min: 90, ideal: 110)
                TableColumn(L10n.t("col.project")) { s in Text(s.project) }
                    .width(min: 140, ideal: 220)
                TableColumn(L10n.t("col.requests")) { s in Text("\(s.requests)") }
                TableColumn(L10n.t("col.tokens")) { s in
                    Text(formatTokens(Double(s.totalTokens))).monospacedDigit()
                }
                TableColumn(L10n.t("col.cost")) { s in
                    if let cost = s.costUsd {
                        Text(String(format: "%.2f %@", cost, dashboard.currency)).monospacedDigit()
                    }
                }
            }
            if let selected = dashboard.sessions.first(where: { $0.sessionId == sessionSelection }) {
                Divider()
                sessionInspector(selected, currency: dashboard.currency)
                    .padding(16)
            }
        }
        .padding(8)
    }

    /// Native inspector for the selected session row: full metadata and a
    /// copy button for the id.
    private func sessionInspector(_ row: SessionRow, currency: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title ?? row.shortId).font(.title3.weight(.semibold))
                    HStack(spacing: 4) {
                        Text(L10n.t("sessions.detail.id")).font(.caption).foregroundStyle(.secondary)
                        CopyIdButton(sessionId: row.sessionId)
                    }
                }
                Spacer()
                if row.isActive {
                    Label(L10n.t("sessions.detail.live"), systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            sessionDetail(L10n.t("sessions.detail.project"), row.project)
            sessionDetail(L10n.t("sessions.detail.title_source"), row.titleSource ?? "auto")
            if let startedMs = row.startedMs {
                sessionDetail(L10n.t("sessions.detail.started"), sessionDateTime(startedMs))
            }
            sessionDetail(L10n.t("sessions.detail.usage"),
                          L10n.t("row.req_tok", row.requests, formatTokens(Double(row.totalTokens))))
            if let cost = row.costUsd {
                sessionDetail(L10n.t("sessions.detail.cost"), String(format: "%.2f %@", cost, currency))
            }
            if row.subagent {
                Text(L10n.t("sessions.detail.subagent")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Projects

    private func projectsSection(_ dashboard: DashboardReport) -> some View {
        let total = dashboard.projects.map { $0.totalTokens }.reduce(0, +)
        // No ScrollView around the Table: it needs a bounded height and
        // scrolls natively inside the detail pane.
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                MetricCard(
                    title: L10n.t("section.projects"),
                    value: "\(dashboard.projects.count)",
                    subtitle: L10n.t("metric.projects.sub", formatTokens(Double(total))),
                    symbol: "folder")
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Table(dashboard.projects.sorted { $0.totalTokens > $1.totalTokens }) {
                TableColumn(L10n.t("col.project")) { row in
                    Text(row.key).fontWeight(.medium)
                }.width(min: 200, ideal: 320)
                TableColumn(L10n.t("col.share")) { row in
                    let share = total > 0 ? Double(row.totalTokens) / Double(total) * 100 : 0
                    Text(String(format: "%.0f%%", share)).monospacedDigit()
                }.width(min: 70, ideal: 90)
                TableColumn(L10n.t("col.tokens")) { row in
                    Text(formatTokens(Double(row.totalTokens))).monospacedDigit()
                }.width(min: 110, ideal: 140)
                TableColumn("") { row in
                    ProgressView(value: Double(row.totalTokens), total: Double(max(total, 1)))
                        .frame(width: 120)
                }.width(min: 130, ideal: 150)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Settings

    /// Idiomatic settings, kapitsa style: a grouped Form with a header card,
    /// labeled rows (label left, control right) and a reset footer.
    private var settingsForm: some View {
        Form {
            Section {
                HStack {
                    Image(nsImage: MistralIcon.image(style: .logo, live: false, colorMode: .color))
                        .resizable().scaledToFit().frame(width: 28, height: 28)
                    Text("Miaou").font(.system(.title3, design: .rounded).weight(.bold))
                    Spacer()
                    Text(L10n.t("version.display", appVersion))
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Text(L10n.t("settings.tagline")).foregroundStyle(.secondary)
            }
            Section(L10n.t("settings.section.bar")) {
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
                .id("barMode-\(languageRaw)")
                Toggle(L10n.t("icon.toggle"), isOn: $showIcon)
                    .disabled(barMode == .none)
                Toggle(L10n.t("dock.toggle"), isOn: $showInDock)
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
                Picker(L10n.t("settings.language"), selection: $languageRaw) {
                    Text(L10n.t("language.system")).tag("system")
                    Text(L10n.t("language.french")).tag("fr")
                    Text(L10n.t("language.english")).tag("en")
                }
                .pickerStyle(.segmented)
                if let loginError {
                    Text(loginError).foregroundStyle(.red)
                }
            }
            Section(L10n.t("icon.headline")) {
                Picker(L10n.t("icon.style"), selection: $barIconRaw) {
                    ForEach(BarIconStyle.allCases) { style in
                        Text(style.label).tag(style.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .id("iconStyle-\(languageRaw)")
                Picker(L10n.t("colorMode.picker"), selection: $chatonColorRaw) {
                    ForEach(ChatonColorMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .id("colorMode-\(languageRaw)")
                // When the menu bar pet animates: always, or only while a
                // Vibe session is live. Only meaningful with a pet icon.
                Picker(L10n.t("widget.chaton.mode"), selection: $barAnimationRaw) {
                    ForEach(ChatonAnimationMode.allCases, id: \.rawValue) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .id("barAnimation-\(languageRaw)")
                .disabled(BarIconStyle(rawValue: barIconRaw) == .logo)
            }
            Section(L10n.t("desktopPet.headline")) {
                Toggle(L10n.t("desktopPet.toggle"), isOn: $desktopPetEnabled)
                Toggle(L10n.t("desktopPet.colorDuringMovement"), isOn: $desktopPetColorDuringMovement)
                    .disabled(!desktopPetEnabled)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(L10n.t("desktopPet.glassIntensity"))
                        Spacer()
                        Text(1 - desktopPetGlassTransparency,
                             format: .percent.precision(.fractionLength(0)).locale(L10n.locale))
                            .monospacedDigit()
                    }
                    Slider(value: Binding(
                        get: { 1 - desktopPetGlassTransparency },
                        set: { desktopPetGlassTransparency = 1 - $0 }
                    ), in: 0...1, step: 0.01) {
                        Text(L10n.t("desktopPet.glassIntensity"))
                    }
                    .labelsHidden()
                    .accessibilityValue(Text(1 - desktopPetGlassTransparency,
                                             format: .percent.precision(.fractionLength(0)).locale(L10n.locale)))
                    HStack {
                        Text(L10n.t("desktopPet.glassHidden"))
                        Spacer()
                        Text(L10n.t("desktopPet.glassMaximum"))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .disabled(!desktopPetEnabled)
                Text(L10n.t("desktopPet.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button(L10n.t("settings.reset")) { resetSettings() }
            }
        }
        .formStyle(.grouped)
    }

    private func resetSettings() {
        barModeRaw = BarMode.percent.rawValue
        barIconRaw = BarIconStyle.logo.rawValue
        chatonColorRaw = ChatonColorMode.session.rawValue
        barAnimationRaw = ChatonAnimationMode.session.rawValue
        showIcon = true
        showInDock = true
        desktopPetEnabled = false
        desktopPetColorDuringMovement = true
        desktopPetGlassTransparency = 0
        languageRaw = "system"
    }
}
