import XCTest
@testable import Miaou

final class SessionActivityTests: XCTestCase {
    private func session(_ id: String = "ghost", token: String = "lease:turn-1") -> ActiveSessionReport {
        ActiveSessionReport(id: id, ageMs: 600_000, activityToken: token)
    }

    private func dashboard(_ sessions: [ActiveSessionReport]) -> DashboardReport {
        let totals = TotalsReport(requests: 2, inputTokens: 10, outputTokens: 5,
                                  cachedInputTokens: 0, totalTokens: 15, costUsd: 42)
        let rows = sessions.map {
            SessionRow(sessionId: $0.id, shortId: $0.id, project: "project", title: nil,
                       active: true, subagent: false, startedMs: nil, requests: 2,
                       inputTokens: 10, outputTokens: 5, cachedInputTokens: 0,
                       totalTokens: 15, costUsd: 42)
        }
        return DashboardReport(
            generatedAtMs: 100, today: "2026-11-12", currentMonth: "2026-11",
            activeModel: nil, currency: "€", plan: nil, totals: totals,
            todayTotals: totals, monthToDate: totals,
            budgetStatus: BudgetStatusReport(
                month: "2026-11", usedUsd: 42, usedTokens: 15, usedRequests: 2,
                budget: BudgetReport(monthlyUsd: 255, overageUsd: nil,
                                     overageAllowed: false, monthlyTokens: nil)),
            anchor: nil, daily: [], monthly: [], projects: [], sessions: rows, active: sessions)
    }

    func testForceIdleClearsOnlyThisTurnAcrossRefreshesAndRelaunches() {
        let ghost = session()
        let other = session("other")
        let report = dashboard([ghost, other])
        var activity = SessionActivity()
        activity.record(ActivityReport(generatedAtMs: report.generatedAtMs + 1, active: [ghost, other]))
        activity.forceIdle(ghost)
        let idle = activity.applying(to: report)
        XCTAssertEqual(idle.liveSessions.map(\.id), ["other"])
        XCTAssertFalse(idle.sessions[0].isActive)
        XCTAssertTrue(idle.sessions[1].isActive)
        XCTAssertEqual(idle.totals, report.totals)
        XCTAssertEqual(idle.sessions[0].totalTokens, report.sessions[0].totalTokens)

        // Reloading the saved preferences must not resurrect the same turn.
        var relaunched = SessionActivity(forcedIdleTokens: activity.forcedIdleTokens)
        relaunched.record(ActivityReport(generatedAtMs: report.generatedAtMs + 2, active: [ghost, other]))
        XCTAssertEqual(relaunched.applying(to: report).liveSessions.map(\.id), ["other"])
        relaunched.restoreAutomaticDetection()
        XCTAssertEqual(relaunched.applying(to: report).liveSessions.map(\.id), ["ghost", "other"])
    }

    func testNewTurnOrLeaseRestoresDetectionAndOldResponsesCannotUndoIt() {
        for newToken in ["lease:turn-2", "new-lease:turn-1"] {
            let ghost = session()
            let report = dashboard([ghost])
            let time = report.generatedAtMs
            var activity = SessionActivity()
            activity.record(ActivityReport(generatedAtMs: time + 1, active: [ghost]))
            activity.forceIdle(ghost)
            activity.record(ActivityReport(generatedAtMs: time, active: []))
            XCTAssertTrue(activity.applying(to: report).liveSessions.isEmpty)
            XCTAssertEqual(activity.forcedIdleTokens["ghost"], ghost.activityToken)

            let resumed = session(token: newToken)
            activity.record(ActivityReport(generatedAtMs: time + 3, active: [resumed]))
            XCTAssertTrue(activity.forcedIdleTokens.isEmpty)
            XCTAssertEqual(activity.applying(to: report).liveSessions, [resumed])
            // Clicking an outdated row must not hide the newer task.
            activity.forceIdle(ghost)
            XCTAssertTrue(activity.forcedIdleTokens.isEmpty)
            activity.record(ActivityReport(generatedAtMs: time + 2, active: [ghost]))
            XCTAssertEqual(activity.applying(to: report).liveSessions, [resumed])
        }
    }

    func testDashboardIsFilteredEvenWhenItsTimestampIsNewerThanTheActivityPoll() {
        let ghost = session()
        let report = dashboard([ghost])
        var activity = SessionActivity()
        activity.record(ActivityReport(generatedAtMs: report.generatedAtMs - 1, active: [ghost]))
        activity.forceIdle(ghost)
        XCTAssertTrue(activity.applying(to: report).liveSessions.isEmpty)
        XCTAssertFalse(activity.applying(to: report).sessions[0].isActive)
    }

    func testForceIdleUpdatesTheWidgetAndPersistsWhileTheSessionIsAbsent() {
        let ghost = session()
        let report = dashboard([ghost])
        var activity = SessionActivity()
        activity.record(ActivityReport(generatedAtMs: report.generatedAtMs + 1, active: [ghost]))
        activity.forceIdle(ghost)
        let widget = MiaouWidgetSnapshot(dashboard: activity.applying(to: report), language: "fr")
        XCTAssertNil(widget.activityExpiresAt)
        activity.record(ActivityReport(generatedAtMs: report.generatedAtMs + 2, active: []))
        activity.record(ActivityReport(generatedAtMs: report.generatedAtMs + 3, active: [ghost]))
        XCTAssertTrue(activity.applying(to: report).liveSessions.isEmpty)
    }

    func testLegacyCLIWithoutATokenCannotPermanentlyHideASession() {
        let legacy = ActiveSessionReport(id: "legacy", ageMs: 1)
        let report = dashboard([legacy])
        var activity = SessionActivity()
        activity.record(ActivityReport(generatedAtMs: report.generatedAtMs, active: [legacy]))
        activity.forceIdle(legacy)
        XCTAssertTrue(activity.forcedIdleTokens.isEmpty)
        XCTAssertEqual(activity.applying(to: report).liveSessions, [legacy])
    }
}
