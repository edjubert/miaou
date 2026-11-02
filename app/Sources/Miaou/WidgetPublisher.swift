import Foundation
import WidgetKit
import OSLog

extension MiaouWidgetSnapshot {
    init(dashboard: DashboardReport, language: String) {
        let date = Date(timeIntervalSince1970: Double(dashboard.generatedAtMs) / 1000)
        self.init(
            updatedAt: date, month: dashboard.currentMonth, currency: dashboard.currency,
            language: ["fr", "en"].contains(language) ? language : "system",
            monthCost: dashboard.budgetStatus.usedUsd,
            budgetCost: dashboard.budgetStatus.budget.effectiveUsd,
            monthTokens: dashboard.budgetStatus.usedTokens,
            todayCost: dashboard.todayTotals.costUsd, todayTokens: dashboard.todayTotals.totalTokens,
            todayRequests: dashboard.todayTotals.requests,
            activityExpiresAt: dashboard.liveSessions.isEmpty ? nil :
                date.addingTimeInterval(MiaouWidgetSnapshot.staleInterval),
            daily: dashboard.daily.suffix(14).map { MiaouWidgetDay(day: $0.key, tokens: $0.totalTokens) }
        )
    }
}

final class MiaouWidgetPublisher {
    private let storage: MiaouWidgetStorage?
    private var lastReload = Date.distantPast
    private var signature: String?
    private let reload: () -> Void

    init(storage: MiaouWidgetStorage? = .shared,
         reload: @escaping () -> Void = {
             WidgetCenter.shared.reloadTimelines(ofKind: MiaouWidgetStorage.kind)
         }) {
        self.storage = storage
        self.reload = reload
    }

    func publish(_ dashboard: DashboardReport, language: String, now: Date = Date()) {
        guard let storage else { return }
        let snapshot = MiaouWidgetSnapshot(dashboard: dashboard, language: language)
        do {
            try storage.publish(snapshot)
            let next = "\(snapshot.month)|\(snapshot.currency)|\(snapshot.language)|" +
                "\(dashboard.liveSessions.isEmpty)|\(dashboard.anchor?.atMs ?? 0)|" +
                "\(dashboard.anchor?.cost ?? 0)|\(snapshot.budgetCost ?? 0)"
            if signature != next || now.timeIntervalSince(lastReload) >= 60 {
                signature = next
                lastReload = now
                reload()
            }
        } catch {
            Logger(subsystem: "com.edjubert.Miaou", category: "Widget")
                .error("Cannot publish widget snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }
}
