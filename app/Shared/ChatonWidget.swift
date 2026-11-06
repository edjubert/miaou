import Foundation
import SwiftUI
import WidgetKit
#if canImport(AppIntents)
import AppIntents
#endif

@available(macOS 14.0, *)
extension ChatonAnimationMode: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: LocalizedStringResource(
            "widget.chaton.mode", defaultValue: "Animation"))
    }

    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [
            .always: DisplayRepresentation(
                title: LocalizedStringResource(
                    "widget.chaton.mode.always", defaultValue: "Always")),
            .session: DisplayRepresentation(
                title: LocalizedStringResource(
                    "widget.chaton.mode.session", defaultValue: "When a session is active")),
        ]
    }
}

@available(macOS 14.0, *)
extension BarPet: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: LocalizedStringResource(
            "widget.chaton.pet", defaultValue: "Cat"))
    }

    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [
            .chaton: DisplayRepresentation(title: LocalizedStringResource(
                "iconStyle.chaton", defaultValue: "Chaton")),
            .chonk: DisplayRepresentation(title: LocalizedStringResource(
                "iconStyle.chonk", defaultValue: "Le Chonk")),
        ]
    }
}

/// Choose the pet and when it animates in the macOS Edit Widgets panel.
@available(macOS 14.0, *)
struct ChatonWidgetConfiguration: WidgetConfigurationIntent {
    static var title = LocalizedStringResource(
        "widget.chaton.name", defaultValue: "Chaton")

    @Parameter(title: LocalizedStringResource(
        "widget.chaton.mode", defaultValue: "Animation"),
        default: .session)
    var mode: ChatonAnimationMode

    @Parameter(title: LocalizedStringResource(
        "widget.chaton.pet", defaultValue: "Cat"),
        default: .chaton)
    var pet: BarPet

    init() {
        self.init(mode: .session)
    }

    init(mode: ChatonAnimationMode, pet: BarPet = .chaton) {
        self.mode = mode
        self.pet = pet
    }
}

@available(macOS 14.0, *)
struct ChatonWidgetEntry: TimelineEntry {
    let date: Date
    let frame: Int
    let active: Bool
    let language: String
    let pet: BarPet
}

@available(macOS 14.0, *)
struct ChatonWidgetProvider: AppIntentTimelineProvider {
    typealias Intent = ChatonWidgetConfiguration
    typealias Entry = ChatonWidgetEntry

    func placeholder(in context: Context) -> ChatonWidgetEntry {
        ChatonWidgetEntry(date: Date(), frame: BarPet.chaton.restFrame, active: false,
                          language: "system", pet: .chaton)
    }

    func snapshot(for configuration: ChatonWidgetConfiguration, in context: Context) async -> ChatonWidgetEntry {
        if context.isPreview {
            return ChatonWidgetEntry(date: Date(), frame: 1, active: true,
                                     language: "system", pet: configuration.pet)
        }
        let snapshot = MiaouWidgetStorage.shared?.read()
        let plan = ChatonWidgetPlan.make(mode: configuration.mode, snapshot: snapshot,
                                         pet: configuration.pet)
        let pose = plan.entries[0]
        return ChatonWidgetEntry(date: pose.date, frame: pose.frame, active: pose.active,
                                 language: snapshot?.language ?? "system", pet: configuration.pet)
    }

    func recommendations() -> [AppIntentRecommendation<ChatonWidgetConfiguration>] {
        ChatonAnimationMode.allCases.map { mode in
            AppIntentRecommendation(
                intent: ChatonWidgetConfiguration(mode: mode),
                description: mode == .always
                    ? LocalizedStringResource(
                        "widget.chaton.mode.always", defaultValue: "Always")
                    : LocalizedStringResource(
                        "widget.chaton.mode.session", defaultValue: "When a session is active"))
        }
    }

    func timeline(for configuration: ChatonWidgetConfiguration, in context: Context) async -> Timeline<ChatonWidgetEntry> {
        let now = Date()
        let snapshot = MiaouWidgetStorage.shared?.read()
        let plan = ChatonWidgetPlan.make(now: now, mode: configuration.mode, snapshot: snapshot,
                                         pet: configuration.pet)
        let language = snapshot?.language ?? "system"
        return Timeline(entries: plan.entries.map {
            ChatonWidgetEntry(date: $0.date, frame: $0.frame, active: $0.active,
                              language: language, pet: configuration.pet)
        }, policy: .after(plan.reloadAfter))
    }
}

/// Five stable vector shapes replace hundreds of individual dot views.
/// This keeps the timeline archive small enough for WidgetKit and swaps
/// paths instantly, without crossfading rasterized Canvas snapshots.
@available(macOS 14.0, *)
struct PetGlyphView: View {
    let frame: Int
    let live: Bool
    let pet: BarPet

    var body: some View {
        GeometryReader { geometry in
            let palette: [Color] = (live ? MistralLogo.brand : MistralLogo.grayscale)
                .map(Color.init(nsColor:))
            let visible = pet.visibleDots(frame: frame)
            let dots = pet.dotSlots(size: geometry.size)
            ZStack(alignment: .topLeading) {
                ForEach(0..<5) { band in
                    PetDotBand(rects: dots.filter {
                        visible.contains($0.id) && min(4, $0.row * 5 / pet.gridHeight) == band
                    }.map(\.rect))
                    .fill(palette[band])
                    .contentTransition(.identity)
                    .animation(.linear(duration: 0), value: frame)
                }
            }
        }
        .transition(.identity)
        .animation(.linear(duration: 0), value: frame)
        .animation(.linear(duration: 0), value: pet)
    }
}

private struct PetDotBand: Shape {
    let rects: [CGRect]

    func path(in rect: CGRect) -> Path {
        Path { path in
            for dot in rects {
                path.addRect(dot)
            }
        }
    }
}

/// Desktop widget that only shows the selected animated pet.
@available(macOS 14.0, *)
struct MiaouChatonWidgetView: View {
    let entry: ChatonWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        PetGlyphView(frame: entry.frame, live: entry.active, pet: entry.pet)
            .padding(family == .systemSmall ? 4 : 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(for: .widget) {
                Color(nsColor: .windowBackgroundColor)
            }
            .widgetURL(URL(string: "miaou://dashboard"))
            .accessibilityLabel(L10n.t(entry.pet == .chonk ? "widget.chonk.label" : "widget.chaton.label",
                                       language: entry.language))
    }
}

@available(macOS 14.0, *)
struct MiaouChatonWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: ChatonWidgetPlan.chatonKind, provider: ChatonWidgetProvider()) { entry in
            MiaouChatonWidgetView(entry: entry)
        }
        .configurationDisplayName(LocalizedStringResource(
            "widget.chaton.name", defaultValue: "Chaton"))
        .description(LocalizedStringResource(
            "widget.chaton.description", defaultValue: "The animated Chaton or Le Chonk."))
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
