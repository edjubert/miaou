import SwiftUI
import WidgetKit

struct MiaouWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MiaouWidgetEntry {
        MiaouWidgetEntry(date: Date(), snapshot: .example)
    }

    func getSnapshot(in context: Context, completion: @escaping (MiaouWidgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) :
            MiaouWidgetEntry(date: Date(), snapshot: MiaouWidgetStorage.shared?.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MiaouWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = MiaouWidgetStorage.shared?.read()
        var dates = [now]
        if let snapshot {
            dates += [snapshot.activityExpiresAt,
                      snapshot.updatedAt.addingTimeInterval(MiaouWidgetSnapshot.staleInterval)]
                .compactMap { $0 }.filter { $0 > now }
            if let nextDay = Calendar.current.dateInterval(of: .day, for: now)?.end {
                dates.append(nextDay)
            }
            if let nextMonth = Calendar.current.dateInterval(of: .month, for: now)?.end {
                dates.append(nextMonth)
            }
        }
        // Scheduled entries expire activity and old-month data even if
        // macOS delays the next provider invocation.
        let entries = Set(dates).sorted().map { MiaouWidgetEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(60))))
    }
}

@main
struct MiaouWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MiaouWidgetStorage.kind, provider: MiaouWidgetProvider()) { entry in
            MiaouWidgetView(entry: entry)
        }
        .configurationDisplayName("Miaou")
        .description(LocalizedStringKey("widget.description"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
