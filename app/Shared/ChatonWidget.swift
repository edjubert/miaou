import Foundation
import SwiftUI
import WidgetKit
#if canImport(AppIntents)
import AppIntents
#endif

@available(macOS 14.0, *)
extension ChatonAnimationMode: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: LocalizedStringResource("widget.chaton.mode"))
    }

    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [
            .always: DisplayRepresentation(
                title: LocalizedStringResource("widget.chaton.mode.always")),
            .session: DisplayRepresentation(
                title: LocalizedStringResource("widget.chaton.mode.session")),
        ]
    }
}

/// Widget configuration: how often the chaton animates. The parameter
/// shows up in the macOS Edit Widgets panel.
@available(macOS 14.0, *)
struct ChatonWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "widget.chaton.name"

    @Parameter(title: "widget.chaton.mode", default: .session)
    var mode: ChatonAnimationMode

    init() {
        self.init(mode: .session)
    }

    init(mode: ChatonAnimationMode) {
        self.mode = mode
    }
}

@available(macOS 14.0, *)
struct ChatonWidgetEntry: TimelineEntry {
    let date: Date
    let frame: Int
    let active: Bool
    let language: String
}

@available(macOS 14.0, *)
struct ChatonWidgetProvider: AppIntentTimelineProvider {
    typealias Intent = ChatonWidgetConfiguration
    typealias Entry = ChatonWidgetEntry

    func placeholder(in context: Context) -> ChatonWidgetEntry {
        ChatonWidgetEntry(date: Date(), frame: Chaton.restFrame, active: false, language: "system")
    }

    func snapshot(for configuration: ChatonWidgetConfiguration, in context: Context) async -> ChatonWidgetEntry {
        if context.isPreview {
            return ChatonWidgetEntry(date: Date(), frame: 1, active: true, language: "system")
        }
        let snapshot = MiaouWidgetStorage.shared?.read()
        let plan = ChatonWidgetPlan.make(mode: configuration.mode, snapshot: snapshot)
        return plan.entries.first.map {
            ChatonWidgetEntry(date: $0.date, frame: $0.frame, active: $0.active,
                              language: snapshot?.language ?? "system")
        } ?? placeholder(in: context)
    }

    func recommendations() -> [AppIntentRecommendation<ChatonWidgetConfiguration>] {
        ChatonAnimationMode.allCases.map { mode in
            AppIntentRecommendation(
                intent: ChatonWidgetConfiguration(mode: mode),
                description: mode == .always
                    ? LocalizedStringResource("widget.chaton.mode.always")
                    : LocalizedStringResource("widget.chaton.mode.session"))
        }
    }

    func timeline(for configuration: ChatonWidgetConfiguration, in context: Context) async -> Timeline<ChatonWidgetEntry> {
        let now = Date()
        let snapshot = MiaouWidgetStorage.shared?.read()
        let plan = ChatonWidgetPlan.make(now: now, mode: configuration.mode, snapshot: snapshot)
        let language = snapshot?.language ?? "system"
        return Timeline(entries: plan.entries.map {
            ChatonWidgetEntry(date: $0.date, frame: $0.frame, active: $0.active, language: language)
        }, policy: .after(plan.reloadAfter))
    }
}

/// Each possible dot keeps the same view identity across all poses.
/// WidgetKit crossfades Canvas snapshots even with an identity content
/// transition, so animate visibility on native shapes with zero duration.
@available(macOS 14.0, *)
struct ChatonGlyphView: View {
    let frame: Int
    let live: Bool

    var body: some View {
        GeometryReader { geometry in
            let palette: [Color] = (live ? MistralLogo.brand : MistralLogo.grayscale)
                .map(Color.init(nsColor:))
            let index = min(max(frame, 0), Chaton.frames.count - 1)
            let visible = Set(Chaton.frames[index].map(Chaton.key))
            ZStack(alignment: .topLeading) {
                ForEach(Chaton.dotSlots(size: geometry.size), id: \.id) { dot in
                    let opacity = visible.contains(dot.id) ? 1.0 : 0.0
                    Rectangle()
                        .fill(palette[min(4, dot.row * 5 / 12)])
                        .frame(width: dot.rect.width, height: dot.rect.height)
                        .position(x: dot.rect.midX, y: dot.rect.midY)
                        .opacity(opacity)
                        .animation(.linear(duration: 0), value: opacity)
                }
            }
        }
        .transition(.identity)
        .animation(.linear(duration: 0), value: frame)
    }
}

/// Desktop widget that only shows the animated chaton.
@available(macOS 14.0, *)
struct MiaouChatonWidgetView: View {
    let entry: ChatonWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        ChatonGlyphView(frame: entry.frame, live: entry.active)
            .padding(family == .systemSmall ? 16 : 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(for: .widget) {
                Color(nsColor: .windowBackgroundColor)
            }
            .widgetURL(URL(string: "miaou://dashboard"))
            .accessibilityLabel(L10n.t("widget.chaton.label", language: entry.language))
    }
}

@available(macOS 14.0, *)
struct MiaouChatonWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: ChatonWidgetPlan.chatonKind, provider: ChatonWidgetProvider()) { entry in
            MiaouChatonWidgetView(entry: entry)
        }
        .configurationDisplayName(LocalizedStringResource("widget.chaton.name"))
        .description(LocalizedStringResource("widget.chaton.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
