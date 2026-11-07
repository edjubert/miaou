import SwiftUI
import AppKit
import Charts
import ServiceManagement

@main
struct MiaouApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Window("Miaou", id: "main") {
            MainWindow()
                .environmentObject(AppModel.shared)
                .onOpenURL { url in
                    guard url.scheme == "miaou", url.host == "dashboard" else { return }
                    MainWindowFocus.activate()
                }
        }
        .defaultSize(width: 680, height: 640)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                OpenMainWindowCommand()
            }
        }
        MenuBarExtra {
            MenuContent()
                .environmentObject(AppModel.shared)
        } label: {
            BarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

/// Cmd+0 / menu item that opens the main window, like kapitsa's desktop.
struct OpenMainWindowCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(L10n.t("window.open")) {
            openWindow(id: "main")
            MainWindowFocus.activate()
        }
        .keyboardShortcut("0", modifiers: .command)
    }
}

/// The menu bar label lives in its own View: observation at the App/Scene
/// level does not reliably refresh MenuBarExtra labels, a dedicated
/// observed view does.
struct BarLabel: View {
    @ObservedObject private var model = AppModel.shared
    @StateObject private var animator = PetAnimator()
    @AppStorage("barMode") private var barModeRaw: String = BarMode.percent.rawValue
    @AppStorage("barIcon") private var barIconRaw: String = BarIconStyle.logo.rawValue
    @AppStorage("chatonColor") private var chatonColorRaw: String = ChatonColorMode.session.rawValue
    @AppStorage("barAnimation") private var barAnimationRaw: String = ChatonAnimationMode.session.rawValue
    @AppStorage("showIcon") private var showIcon: Bool = true

    private var style: BarIconStyle {
        BarIconStyle(rawValue: barIconRaw) ?? .logo
    }

    private var colorMode: ChatonColorMode {
        ChatonColorMode(rawValue: chatonColorRaw) ?? .session
    }

    private var animationMode: ChatonAnimationMode {
        ChatonAnimationMode(rawValue: barAnimationRaw) ?? .session
    }

    private var mode: BarMode {
        BarMode(rawValue: barModeRaw) ?? .percent
    }

    /// A bar without text always keeps its icon.
    private var showsIcon: Bool {
        showIcon || mode == .none
    }

    /// The glyph actually shown: the chonk when Vibe's active model is
    /// Le Chonk (like the Vibe CLI banner), unless the logo is selected.
    private var pet: BarPet? {
        switch style {
        case .logo: return nil
        case .chonk: return .chonk
        case .chaton: return model.isChonkModel ? .chonk : .chaton
        }
    }

    /// The icon style matching the pet: a chonk model turns a chaton
    /// selection into the chonk glyph.
    private var effectiveStyle: BarIconStyle {
        pet == .chonk ? .chonk : style
    }

    /// The pet loops according to the animation setting: always, or only
    /// while a session is live, resting on its sleeping pose otherwise.
    private var animate: Bool {
        pet != nil && (animationMode == .always || model.hasLiveSessions)
    }

    var body: some View {
        HStack(spacing: 4) {
            if showsIcon {
                Image(nsImage: MistralIcon.image(
                    style: effectiveStyle,
                    live: model.hasLiveSessions,
                    frame: animator.frame,
                    colorMode: colorMode
                ))
            }
            if mode != .none {
                Text(model.barTitle(mode: mode))
            }
        }
        .onAppear {
            if let pet { animator.setPet(pet) }
            animator.setActive(animate)
        }
        .onChange(of: animate) { active in
            animator.setActive(active)
        }
        .onChange(of: pet) { newPet in
            if let newPet { animator.setPet(newPet) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let desktopPet = DesktopPetController()

    deinit {
        UserDefaults.standard.removeObserver(self, forKeyPath: "showInDock")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Regular app by default: the main window needs a Dock presence
        // and normal activation, like kapitsa's desktop window. The
        // "showInDock" setting turns Miaou into a menu-bar-only
        // (accessory) app, hiding its Dock icon.
        applyDockPolicy()
        UserDefaults.standard.addObserver(self, forKeyPath: "showInDock",
                                          options: [.new], context: nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        MiaouWidgetRefreshRouter.refresh = { AppModel.shared.refresh() }
        AppModel.shared.refresh()
        desktopPet.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        desktopPet.stop()
    }

    /// Dock presence follows the "showInDock" user default, applied live.
    private func applyDockPolicy() {
        let show = UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? true
        NSApplication.shared.setActivationPolicy(show ? .regular : .accessory)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "showInDock" {
            DispatchQueue.main.async { self.applyDockPolicy() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// The pet as a full-width banner at the top of the menu window,
/// looping like the Vibe CLI banner it comes from, resting a while on
/// its rest pose each time the cycle reaches it. Shows the chonk when
/// Vibe's active model is Le Chonk, the petit chat otherwise.
struct PetBanner: View {
    @ObservedObject private var model = AppModel.shared
    @StateObject private var animator = PetAnimator(restsInLoop: true)
    @AppStorage("chatonColor") private var chatonColorRaw: String = ChatonColorMode.session.rawValue

    private var colorMode: ChatonColorMode {
        ChatonColorMode(rawValue: chatonColorRaw) ?? .session
    }

    private var pet: BarPet {
        model.isChonkModel ? .chonk : .chaton
    }

    // Fixed height: a resizable image with aspectRatio fit has no
    // intrinsic size, so a height-starved VStack squeezes it to zero
    // and the banner vanishes.
    static let height: CGFloat = 132

    var body: some View {
        Image(nsImage: MistralIcon.bannerImage(frame: animator.frame, pet: pet, colorMode: colorMode))
            .resizable()
            .aspectRatio(pet.barWindow.width / pet.barWindow.height, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .onAppear {
                animator.setPet(pet)
                animator.setActive(true)
            }
            .onDisappear { animator.setActive(false) }
            .onChange(of: pet) { newPet in
                animator.setPet(newPet)
            }
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
        case .chonk: return L10n.t("iconStyle.chonk")
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

extension ChatonAnimationMode {
    var label: String {
        switch self {
        case .always: return L10n.t("widget.chaton.mode.always")
        case .session: return L10n.t("widget.chaton.mode.session")
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var anchorCostText: String = ""
    @State private var anchorError: String?
    @State private var isAddingAnchor: Bool = false

    /// App version from the bundle plist, stamped by `make app` from the
    /// CLI's Cargo.toml version. "dev" when run via `swift run`.
    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PetBanner()
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
                Button(L10n.t("window.open")) {
                    openWindow(id: "main")
                    MainWindowFocus.activate()
                }
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
            anchorInput(dashboard)
            if let anchor = dashboard.anchor {
                Text(L10n.t("budget.anchor", anchor.cost, dashboard.currency, anchorTime(anchor.atMs)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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

    /// Cost input stays available even before the first Console anchor.
    private func anchorInput(_ dashboard: DashboardReport) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                TextField(L10n.t("anchor.placeholder", dashboard.currency), text: $anchorCostText)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isAddingAnchor)
                    .onSubmit { addAnchor() }
                Button(L10n.t("anchor.button")) { addAnchor() }
                    .font(.caption)
                    .disabled(ConsoleCost.parse(anchorCostText) == nil || isAddingAnchor)
            }
            if let anchorError {
                Text(anchorError)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    private func addAnchor() {
        guard !isAddingAnchor, let cost = ConsoleCost.parse(anchorCostText) else { return }
        isAddingAnchor = true
        anchorError = nil
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try MiaouCLI.addAnchor(cost: cost)
                DispatchQueue.main.async {
                    self.isAddingAnchor = false
                    self.anchorCostText = ""
                    self.model.refresh()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isAddingAnchor = false
                    switch error {
                    case MiaouError.processFailed(let code):
                        self.anchorError = L10n.t("error.exited", code)
                    case MiaouError.invalidAnchorCost:
                        self.anchorError = L10n.t("error.invalid_anchor_cost")
                    default:
                        self.anchorError = error.localizedDescription
                    }
                }
            }
        }
    }

    /// Localized day and time of a console anchor, e.g. "12 Oct 14:31".
    private func anchorTime(_ ms: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.setLocalizedDateFormatFromTemplate("d MMM HH:mm")
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(ms) / 1000))
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
        LiveSessionsFold(dashboard: dashboard)
    }

    private func overTint(_ dashboard: DashboardReport) -> Color {
        let status = dashboard.budgetStatus
        guard let used = status.usedUsd else { return .accentColor }
        if let effective = status.budget.effectiveUsd, used > effective { return .red }
        if let envelope = status.budget.monthlyUsd, used > envelope { return .orange }
        return .accentColor
    }

}

/// One session row as a fold. Live sessions are marked in the label with
/// `titre title_source.  session_id` and the id copies on click. Unfolding
/// reveals the full session metadata.
struct SessionFold: View {
    let row: SessionRow
    let currency: String

    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            details
        } label: {
            // Full-width tap toggles the fold; the copy button keeps
            // its own hit area inside the label.
            label
                .contentShape(Rectangle())
        }
        .unfoldOnHover(expanded: $expanded)
    }

    /// Live sessions carry `titre + title_source.  session_id`; the others
    /// keep the compact `shortId + project` look.
    private var label: some View {
        HStack(spacing: 6) {
            if row.isActive {
                Text("\(row.title ?? row.project) \(row.titleSource ?? "auto").")
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                CopyIdButton(sessionId: row.sessionId)
            } else {
                Text(row.subagent ? "\(row.shortId)*" : row.shortId)
                    .font(.caption)
                    .monospaced()
                Text(row.project)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(L10n.t("row.req_tok", row.requests, formatTokens(Double(row.totalTokens))))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// All the session metadata, shown when the fold is unfolded (the menu
    /// window clips hover popovers to its scroll area, so no hover panel).
    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(L10n.t("sessions.detail.id"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                CopyIdButton(sessionId: row.sessionId)
            }
            sessionDetail(L10n.t("sessions.detail.project"), row.project)
            if let title = row.title {
                sessionDetail(L10n.t("sessions.detail.title"), title)
            }
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
                Text(L10n.t("sessions.detail.subagent"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if row.isActive {
                Text(L10n.t("sessions.detail.live"))
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
        .padding(.leading, 14)
        .padding(.bottom, 2)
    }
}

/// Click copies the full session id to the pasteboard.
struct CopyIdButton: View {
    let sessionId: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(sessionId, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                copied = false
            }
        } label: {
            Text(copied ? L10n.t("sessions.copied") : sessionId)
                .font(.caption2)
                .monospaced()
                .foregroundStyle(copied ? .green : .secondary)
        }
        .buttonStyle(.plain)
        .help(L10n.t("sessions.copy_help"))
    }
}

/// The live-session section as a fold with a generic label. Unfolded, each
/// running session is a `titre title_source.  session_id` line; clicking
/// the id copies it.
struct LiveSessionsFold: View {
    let dashboard: DashboardReport

    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(dashboard.liveSessions, id: \.id) { live in
                    liveLine(live)
                }
            }
            .padding(.leading, 14)
            .padding(.bottom, 2)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text(L10n.t("live.show_sessions", dashboard.liveSessions.count))
                    .font(.callout)
            }
            .contentShape(Rectangle())
        }
    }

    private func liveLine(_ live: ActiveSessionReport) -> some View {
        var row = dashboard.sessions.first(where: { $0.sessionId == live.id }) ?? SessionRow(
            sessionId: live.id,
            shortId: String(live.id.prefix(8)),
            project: String(live.id.prefix(8)),
            title: live.title,
            subagent: false,
            startedMs: nil,
            requests: 0,
            inputTokens: 0,
            outputTokens: 0,
            cachedInputTokens: 0,
            totalTokens: 0,
            costUsd: nil)
        row.active = true
        row.titleSource = row.titleSource ?? live.titleSource
        // Each live session is its own fold: hover unfolds it to show the
        // metadata, click on the id copies it.
        return SessionFold(row: row, currency: dashboard.currency)
    }
}

/// Expands the fold while the pointer is over it and collapses it when the
/// pointer leaves. The state only flips on enter/leave transitions, not on
/// every mouse move.
struct UnfoldOnHover: ViewModifier {
    @Binding var expanded: Bool
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                switch phase {
                case .active: if !hovered { hovered = true; expanded = true }
                case .ended: if hovered { hovered = false; expanded = false }
                }
            }
    }
}

extension View {
    func unfoldOnHover(expanded: Binding<Bool>) -> some View {
        modifier(UnfoldOnHover(expanded: expanded))
    }
}

func sessionDetail(_ key: String, _ value: String) -> some View {
    HStack(spacing: 4) {
        Text(key)
            .font(.caption2)
            .foregroundStyle(.secondary)
        Text(value)
            .font(.caption2)
            .lineLimit(1)
    }
}

func sessionDateTime(_ ms: Int) -> String {
    let formatter = DateFormatter()
    formatter.locale = L10n.locale
    formatter.setLocalizedDateFormatFromTemplate("d MMM HH:mm")
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(ms) / 1000))
}

/// Daily tokens bar chart. Hovering a bar dims the others and shows a
/// popover with the day and the exact token count; the value labels and
/// the x-axis day labels stay hidden to keep the chart readable at menu
/// size. The y-axis uses localized short units (M/B in English, M/Md in
/// French) instead of scientific notation.
struct DailyChartView: View {
    let days: ArraySlice<PeriodRow>
    /// Chart height: compact in the menu bar, taller in the main window.
    var height: CGFloat = 110

    @State private var hoveredKey: String?

    private var axisFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = L10n.locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.positiveSuffix = L10n.t("chart.unit.suffix")
        return formatter
    }

    private func axisLabel(_ value: Double) -> String {
        let billions = L10n.t("chart.unit.billions")
        let millions = L10n.t("chart.unit.millions")
        if value >= 1_000_000_000 {
            axisFormatter.positiveSuffix = billions
            return axisFormatter.string(from: NSNumber(value: value / 1_000_000_000)) ?? ""
        }
        if value >= 1_000_000 {
            axisFormatter.positiveSuffix = millions
            return axisFormatter.string(from: NSNumber(value: value / 1_000_000)) ?? ""
        }
        axisFormatter.positiveSuffix = ""
        return axisFormatter.string(from: NSNumber(value: value)) ?? ""
    }

    private func dayLabel(_ key: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: key) else { return key }
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("chart.daily.title"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Chart(days, id: \.key) { row in
                BarMark(
                    x: .value(L10n.t("chart.axis.day"), row.key),
                    y: .value(L10n.t("chart.axis.tokens"), row.totalTokens)
                )
                .foregroundStyle(
                    Color.accentColor.opacity(hoveredKey == nil || hoveredKey == row.key ? 0.85 : 0.25)
                )
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let double = value.as(Double.self) {
                            Text(axisLabel(double))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    AxisGridLine()
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    ZStack(alignment: .top) {
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    if let key: String = proxy.value(atX: location.x, as: String.self) {
                                        hoveredKey = key
                                    }
                                case .ended:
                                    hoveredKey = nil
                                }
                            }
                        if let key = hoveredKey, let row = days.first(where: { $0.key == key }) {
                            popover(for: row)
                                .offset(y: -8)
                        }
                    }
                }
            }
            .frame(height: height)
        }
    }

    private func popover(for row: PeriodRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dayLabel(row.key))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(L10n.t("chart.popover.tokens", formatTokens(Double(row.totalTokens))))
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
    }
}
