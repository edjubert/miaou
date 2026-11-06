import Foundation

/// When the pet widget animates. Also the widget's configuration
/// parameter (see the AppEnum conformance in ChatonWidget.swift).
enum ChatonAnimationMode: String, Codable, CaseIterable, Sendable {
    /// The selected pet loops forever.
    case always
    /// The selected pet loops while a Vibe session is active, then freezes on
    /// the rest pose.
    case session
}

/// One planned widget entry: the selected pet's pose to show at a date.
struct ChatonWidgetFrame: Equatable {
    let date: Date
    let frame: Int
    let active: Bool
}

/// WidgetKit receives several cycles ahead of time, with one entry per
/// pose change and a single held entry for each sleeping pause. Every
/// reload samples the shared clock rather than restarting at frame 1.
struct ChatonWidgetPlan {
    /// Widget kind of the chaton widget, shared with the app-side
    /// publisher that reloads it.
    static let chatonKind = "MiaouChaton"

    static let timelineDuration: TimeInterval = 15 * 60
    private static let reloadLead: TimeInterval = 60

    let entries: [ChatonWidgetFrame]
    let reloadAfter: Date

    static func make(now: Date = Date(),
                     mode: ChatonAnimationMode,
                     snapshot: MiaouWidgetSnapshot?,
                     pet: BarPet = .chaton) -> Self {
        let active = snapshot?.isActive(at: now) ?? false
        guard mode == .always || active else {
            return Self(entries: [ChatonWidgetFrame(date: now, frame: pet.restFrame,
                                                    active: false)],
                        reloadAfter: now.addingTimeInterval(60))
        }

        let end = now.addingTimeInterval(timelineDuration)
        // isActive also expires on stale data and a new calendar month.
        let activityEnd: Date? = if active, let snapshot {
            [snapshot.activityExpiresAt,
             snapshot.updatedAt.addingTimeInterval(MiaouWidgetSnapshot.staleInterval),
             Calendar.current.dateInterval(of: .month, for: now)?.end]
                .compactMap { $0 }.min()
        } else {
            nil
        }
        let limit = mode == .session ? min(activityEnd ?? end, end) : end
        var dates = [now]
        var next = PetAnimation.pose(at: now, pet: pet).nextChange
        while next < limit {
            dates.append(next)
            next = PetAnimation.pose(at: next, pet: pet).nextChange
        }
        // Expiration can happen in the middle of a sleeping pause:
        // update the palette (and freeze in session mode) immediately.
        if let activityEnd, activityEnd <= end {
            dates.append(activityEnd)
        }
        let entries = Set(dates).sorted().map { date in
            let live = activityEnd.map { date < $0 } ?? false
            return ChatonWidgetFrame(
                date: date,
                frame: mode == .session && !live ? pet.restFrame :
                    PetAnimation.pose(at: date, pet: pet).frame,
                active: live)
        }
        return Self(entries: entries,
                    reloadAfter: min(end.addingTimeInterval(-reloadLead),
                                     limit.addingTimeInterval(60)))
    }
}
