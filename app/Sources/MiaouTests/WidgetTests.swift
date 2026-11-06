import XCTest
@testable import Miaou

final class WidgetTests: XCTestCase {
    private func fixture(date: Date = Date(), used: Double? = 68.75,
                         anchor: AnchorReport? = nil) -> DashboardReport {
        let totals = TotalsReport(requests: 100, inputTokens: 900, outputTokens: 100,
                                  cachedInputTokens: 800, totalTokens: 1000, costUsd: used)
        let day = PeriodRow(key: "2026-11-02", sessions: 1, requests: 100, inputTokens: 900,
                            outputTokens: 100, cachedInputTokens: 800, totalTokens: 1000, costUsd: used)
        return DashboardReport(
            generatedAtMs: Int(date.timeIntervalSince1970 * 1000), today: day.key,
            currentMonth: MiaouWidgetSnapshot.monthKey(date), activeModel: nil, currency: "€", plan: nil,
            totals: totals, todayTotals: totals, monthToDate: totals,
            budgetStatus: BudgetStatusReport(
                month: MiaouWidgetSnapshot.monthKey(date), usedUsd: used, usedTokens: 1000,
                usedRequests: 100, budget: BudgetReport(monthlyUsd: 255, overageUsd: 50,
                                                       overageAllowed: true, monthlyTokens: nil)),
            anchor: anchor, daily: [day], monthly: [day], projects: [day],
            sessions: [SessionRow(sessionId: "private-session", shortId: "private",
                                  project: "/private/project", title: "private prompt", subagent: false,
                                  startedMs: nil, requests: 100, inputTokens: 900, outputTokens: 100,
                                  cachedInputTokens: 800, totalTokens: 1000, costUsd: used)],
            active: [ActiveSessionReport(id: "private-active", ageMs: 10_000),
                     ActiveSessionReport(id: "old-active", ageMs: 400_000)])
    }

    func testSnapshotKeepsCurrencyBudgetAndMetricsWithoutSessionDetails() throws {
        let dashboard = fixture()
        let value = MiaouWidgetSnapshot(dashboard: dashboard, language: "fr")
        XCTAssertTrue(value.valid)
        XCTAssertEqual(value.currency, "€")
        XCTAssertEqual(value.monthCost, 68.75)
        XCTAssertEqual(value.budgetCost, 305)
        XCTAssertEqual(value.remainingCost, 236.25)
        XCTAssertEqual(value.todayRequests, 100)
        XCTAssertEqual(value.daily.map(\.tokens), [1000])
        XCTAssertEqual(value.language, "fr")
        let json = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        for privateValue in ["private-session", "/private/project", "private prompt", "private-active"] {
            XCTAssertFalse(json.contains(privateValue))
        }
        let noCost = MiaouWidgetSnapshot(dashboard: fixture(used: nil), language: "unknown")
        XCTAssertNil(noCost.monthCost, "Unknown cost must not become zero.")
        XCTAssertNil(noCost.budgetFraction)
        XCTAssertEqual(noCost.monthTokens, 1000)
        XCTAssertEqual(noCost.language, "system")
    }

    func testActivityExpiresAndOldMonthIsNotPresentedAsCurrent() throws {
        let now = Date()
        let value = MiaouWidgetSnapshot(dashboard: fixture(date: now), language: "en")
        XCTAssertTrue(value.isActive(at: value.updatedAt))
        XCTAssertTrue(value.isActive(at: value.updatedAt.addingTimeInterval(299)))
        XCTAssertFalse(value.isActive(at: value.updatedAt.addingTimeInterval(300)))
        XCTAssertFalse(value.isStale(at: value.updatedAt.addingTimeInterval(299)))
        XCTAssertTrue(value.isStale(at: value.updatedAt.addingTimeInterval(300)))
        let nextDay = try XCTUnwrap(Calendar.current.dateInterval(of: .day, for: now)?.end)
        XCTAssertTrue(value.isCurrentDay(at: value.updatedAt))
        XCTAssertFalse(value.isCurrentDay(at: nextDay))
        let nextMonth = try XCTUnwrap(Calendar.current.dateInterval(of: .month, for: now)?.end)
        XCTAssertFalse(value.isCurrentMonth(at: nextMonth))
        XCTAssertFalse(value.isActive(at: nextMonth))
    }

    func testActivityFollowsVerifiedSessionsRatherThanLockAge() {
        var dashboard = fixture()
        dashboard.active = [ActiveSessionReport(id: "open-session", ageMs: 600_000)]
        let active = MiaouWidgetSnapshot(dashboard: dashboard, language: "en")
        XCTAssertTrue(active.isActive(at: active.updatedAt))

        dashboard.active = []
        let inactive = MiaouWidgetSnapshot(dashboard: dashboard, language: "en")
        XCTAssertNil(inactive.activityExpiresAt)
        XCTAssertFalse(inactive.isActive(at: inactive.updatedAt))
    }

    func testSharedStorageRejectsInvalidVersionsPublicFilesAndSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = MiaouWidgetStorage(directory: root.appendingPathComponent("shared"))
        let value = MiaouWidgetSnapshot(dashboard: fixture(), language: "fr")
        try storage.publish(value)
        XCTAssertEqual(storage.read(), value)
        let attributes = try FileManager.default.attributesOfItem(atPath: storage.snapshotURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        var invalid = value
        invalid.version = 2
        try JSONEncoder().encode(invalid).write(to: storage.snapshotURL)
        XCTAssertNil(storage.read())
        try storage.publish(value)
        try FileManager.default.setAttributes([.posixPermissions: 0o644],
                                             ofItemAtPath: storage.snapshotURL.path)
        XCTAssertNil(storage.read())
        let outside = root.appendingPathComponent("outside.json")
        try JSONEncoder().encode(value).write(to: outside)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outside.path)
        try FileManager.default.removeItem(at: storage.snapshotURL)
        try FileManager.default.createSymbolicLink(at: storage.snapshotURL, withDestinationURL: outside)
        XCTAssertNil(storage.read())
        try storage.publish(value)
        XCTAssertEqual(storage.read(), value, "Atomic publish replaces the link itself.")
    }

    func testPublisherWritesEverySnapshotAndReloadsOnAnchorLanguageOrIntervalChange() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = MiaouWidgetStorage(directory: root.appendingPathComponent("shared"))
        var reloads = 0
        let publisher = MiaouWidgetPublisher(storage: storage, reload: { reloads += 1 })
        let now = Date()
        publisher.publish(fixture(date: now), language: "fr", now: now)
        publisher.publish(fixture(date: now.addingTimeInterval(20), used: 70),
                          language: "fr", now: now.addingTimeInterval(20))
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(storage.read()?.monthCost, 70)
        publisher.publish(fixture(date: now), language: "en", now: now.addingTimeInterval(30))
        XCTAssertEqual(reloads, 2)
        publisher.publish(fixture(date: now, anchor: AnchorReport(atMs: 1, cost: 90, deltaUsd: nil)),
                          language: "en", now: now.addingTimeInterval(40))
        XCTAssertEqual(reloads, 3)
        publisher.publish(fixture(date: now, anchor: AnchorReport(atMs: 1, cost: 90, deltaUsd: nil)),
                          language: "en", now: now.addingTimeInterval(100))
        XCTAssertEqual(reloads, 4)
    }

    @MainActor
    func testRefreshIntentUsesContainingAppHandler() async throws {
        defer { MiaouWidgetRefreshRouter.refresh = nil }
        MiaouWidgetRefreshRouter.refresh = nil
        do {
            _ = try await RefreshMiaouIntent().perform()
            XCTFail("A missing containing app handler must report an error.")
        } catch {}
        var calls = 0
        MiaouWidgetRefreshRouter.refresh = { calls += 1 }
        _ = try await RefreshMiaouIntent().perform()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(L10n.t("widget.open_app", language: "fr"), "Ouvrir Miaou")
        XCTAssertEqual(L10n.t("widget.open_app", language: "en"), "Open Miaou")
    }
}
