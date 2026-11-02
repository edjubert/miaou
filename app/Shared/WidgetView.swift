import SwiftUI
import Charts
import WidgetKit

struct MiaouWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: MiaouWidgetSnapshot?
}

@available(macOS 14.0, *)
struct MiaouWidgetView: View {
    let entry: MiaouWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var accent: Color {
        if let fraction = entry.snapshot?.budgetFraction, fraction > 1 { return .red }
        return .orange
    }

    private func t(_ key: String) -> String {
        L10n.t(key, language: entry.snapshot?.language ?? "system")
    }

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, snapshot.isCurrentMonth(at: entry.date) {
                content(snapshot)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    header
                    Spacer(minLength: 0)
                    Text(t("widget.open_app")).font(.headline)
                    Text(t(entry.snapshot == nil ? "widget.no_data" : "widget.new_month"))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(colors: [accent.opacity(0.15), .clear],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .widgetURL(URL(string: "miaou://dashboard"))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(nsImage: MistralIcon.image(style: .logo, live: true, colorMode: .color))
                .resizable().scaledToFit().frame(width: 20, height: 20)
            Text("Miaou").font(.headline)
            Spacer(minLength: 4)
            if entry.snapshot?.isActive(at: entry.date) == true {
                Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(.green)
                    .accessibilityLabel(t("live.active"))
            }
            refreshButton
        }
    }

    private var refreshButton: some View {
        Button(intent: RefreshMiaouIntent()) {
            Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t("widget.refresh.title"))
    }

    private func content(_ value: MiaouWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 10) {
            header
            if family == .systemMedium {
                HStack(alignment: .top, spacing: 20) {
                    month(value).frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(dayName(value)).font(.caption).foregroundStyle(.secondary)
                        if let cost = value.todayCost {
                            Text(money(cost, value)).font(.title3.weight(.semibold))
                        }
                        Text("\(value.todayRequests) \(t("widget.requests"))")
                            .font(.caption).monospacedDigit()
                        Text("\(tokens(value.todayTokens)) tok").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                month(value)
            }
            if family == .systemLarge {
                Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 10) {
                    GridRow {
                        metric(dayName(value), value.todayCost.map { money($0, value) } ??
                               "\(tokens(value.todayTokens)) tok")
                        metric(t("widget.remaining"), value.remainingCost.map { money($0, value) } ?? "—")
                    }
                    GridRow {
                        metric(t(value.isCurrentDay(at: entry.date) ?
                                 "widget.requests_today" : "widget.requests"), String(value.todayRequests))
                        metric(t(value.isCurrentDay(at: entry.date) ?
                                 "widget.tokens_today" : "chart.axis.tokens"), tokens(value.todayTokens))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !value.daily.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("widget.daily")).font(.caption2).foregroundStyle(.secondary)
                        Chart(value.daily, id: \.day) { day in
                            BarMark(x: .value(t("chart.axis.day"), day.day),
                                    y: .value(t("chart.axis.tokens"), day.tokens))
                                .foregroundStyle(accent.gradient)
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .frame(height: 65)
                        .accessibilityLabel(t("widget.daily"))
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                if value.isStale(at: entry.date) {
                    Image(systemName: "clock.badge.exclamationmark")
                    Text(t("widget.last_update"))
                }
                Text(value.updatedAt, style: .relative)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityLabel(t("widget.last_update"))
        }
    }

    private func month(_ value: MiaouWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(monthName(value)).font(.caption).foregroundStyle(.secondary)
            Text(value.monthCost.map { money($0, value) } ?? "\(tokens(value.monthTokens)) tok")
                .font(.system(size: family == .systemSmall ? 27 : 30, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            if let fraction = value.budgetFraction, let budget = value.budgetCost {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(accent.opacity(0.18))
                        Capsule().fill(accent.gradient)
                            .frame(width: geometry.size.width * min(fraction, 1))
                    }
                }
                .frame(height: 5)
                .accessibilityLabel(t("widget.budget_used"))
                .accessibilityValue(String(format: "%.0f%%", fraction * 100))
                HStack {
                    Text(String(format: "%.0f%%", fraction * 100))
                    Spacer(minLength: 2)
                    Text("/ \(money(budget, value))")
                }
                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func money(_ cost: Double, _ value: MiaouWidgetSnapshot) -> String {
        String(format: "%.2f %@", cost, value.currency)
    }

    private func tokens(_ count: Int) -> String {
        for (divisor, suffix) in [(1_000_000_000.0, "B"), (1_000_000.0, "M"), (1_000.0, "k")]
            where Double(count) >= divisor {
            return String(format: "%.1f%@", Double(count) / divisor, suffix)
        }
        return String(count)
    }

    private func monthName(_ value: MiaouWidgetSnapshot) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM"
        guard let date = parser.date(from: value.month) else { return value.month }
        let formatter = DateFormatter()
        formatter.locale = L10n.locale(language: value.language)
        formatter.setLocalizedDateFormatFromTemplate("MMM yyyy")
        return formatter.string(from: date)
    }

    private func dayName(_ value: MiaouWidgetSnapshot) -> String {
        guard !value.isCurrentDay(at: entry.date) else { return t("today.headline") }
        let formatter = DateFormatter()
        formatter.locale = L10n.locale(language: value.language)
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: value.updatedAt)
    }
}
