import Foundation

/// When the chaton widget animates. Also the widget's configuration
/// parameter (see the AppEnum conformance in ChatonWidget.swift).
enum ChatonAnimationMode: String, Codable, CaseIterable, Sendable {
    /// The chaton loops forever.
    case always
    /// The chaton loops while a Vibe session is active, then freezes on
    /// the rest pose.
    case session
}

/// One planned widget entry: the chaton pose to show at a date.
struct ChatonWidgetFrame: Equatable {
    let date: Date
    let frame: Int
    let active: Bool
}

/// Pure timeline plan for the chaton widget, kept free of WidgetKit so
/// the app target and the tests can exercise it. WidgetKit cannot run
/// timers in an extension, so the animation is a timeline of entries
/// spaced one `Chaton.frameInterval` apart over a full cycle, and the
/// reload policy asks for the next cycle right after the last entry.
struct ChatonWidgetPlan {
    /// Widget kind of the chaton widget, shared with the app-side
    /// publisher that reloads it.
    static let chatonKind = "MiaouChaton"

    /// One full animation cycle: 26 transitions of `frameInterval`.
    static let cycleDuration: TimeInterval = 26 * Chaton.frameInterval

    let entries: [ChatonWidgetFrame]
    let reloadAfter: Date

    /// Plans the entries from `now`. In `.session` mode the animation
    /// stops at the snapshot's activity expiration and freezes on the
    /// rest pose; otherwise it loops cycle after cycle. When not
    /// animating, the rest pose is shown and the widget wakes up at the
    /// snapshot's own deadlines (activity expiration, staleness, day
    /// and month boundaries) like the usage widget does.
    static func make(now: Date = Date(),
                     mode: ChatonAnimationMode,
                     snapshot: MiaouWidgetSnapshot?) -> Self {
        let active = snapshot?.isActive(at: now) ?? false
        if mode == .always || active {
            let cycleEnd = now.addingTimeInterval(cycleDuration)
            let limit = if mode == .session, let expires = snapshot?.activityExpiresAt {
                min(expires, cycleEnd)
            } else {
                cycleEnd
            }
            // Dates are computed by index, not accumulated: repeated
            // += frameInterval drifts and can add a 27th entry.
            var entries: [ChatonWidgetFrame] = []
            var frame = 1
            var index = 0
            while now.addingTimeInterval(TimeInterval(index) * Chaton.frameInterval) < limit {
                entries.append(ChatonWidgetFrame(
                    date: now.addingTimeInterval(TimeInterval(index) * Chaton.frameInterval),
                    frame: frame, active: active))
                frame = Chaton.nextFrame(after: frame)
                index += 1
            }
            if mode == .session, let expires = snapshot?.activityExpiresAt,
               expires > now, expires <= cycleEnd {
                entries.append(ChatonWidgetFrame(date: expires, frame: Chaton.restFrame,
                                                 active: false))
                return Self(entries: entries,
                            reloadAfter: expires.addingTimeInterval(Chaton.frameInterval))
            }
            return Self(entries: entries,
                        reloadAfter: now.addingTimeInterval(TimeInterval(entries.count) * Chaton.frameInterval))
        }
        var dates = [now]
        if let snapshot {
            dates += [snapshot.activityExpiresAt,
                      snapshot.updatedAt.addingTimeInterval(MiaouWidgetSnapshot.staleInterval),
                      Calendar.current.dateInterval(of: .day, for: now)?.end,
                      Calendar.current.dateInterval(of: .month, for: now)?.end]
                .compactMap { $0 }
        }
        let wakeups = Set(dates).filter { $0 > now }.sorted()
        return Self(entries: ([now] + wakeups).map {
            ChatonWidgetFrame(date: $0, frame: Chaton.restFrame, active: active)
        }, reloadAfter: now.addingTimeInterval(60))
    }
}
