import XCTest
@testable import Miaou

final class ChatonWidgetTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    private func snapshot(now: Date, expiresIn: TimeInterval? = nil) -> MiaouWidgetSnapshot {
        MiaouWidgetSnapshot(
            updatedAt: now, month: MiaouWidgetSnapshot.monthKey(now), currency: "€",
            language: "en", monthCost: 1, budgetCost: 10, monthTokens: 100,
            todayCost: 1, todayTokens: 10, todayRequests: 1,
            activityExpiresAt: expiresIn.map { now.addingTimeInterval($0) }, daily: [])
    }

    func testAlwaysModePlansMultipleCyclesWithSleepingPauses() {
        let plan = ChatonWidgetPlan.make(now: t0, mode: .always, snapshot: nil)
        XCTAssertGreaterThan(plan.entries.count, 26 * 10)
        XCTAssertLessThan(plan.entries.count, 26 * 60,
                          "A sleeping pause needs one held pose, not frame-rate entries.")
        XCTAssertTrue(plan.entries.allSatisfy { !$0.active })
        var pauses: [TimeInterval] = []
        for (current, next) in zip(plan.entries, plan.entries.dropFirst()) {
            XCTAssertEqual(next.frame, Chaton.nextFrame(after: current.frame))
            let duration = next.date.timeIntervalSince(current.date)
            if current.frame == Chaton.restFrame {
                pauses.append(duration - Chaton.frameInterval)
                XCTAssertGreaterThanOrEqual(duration, 5 + Chaton.frameInterval - 0.0001)
                XCTAssertLessThanOrEqual(duration, 20 + Chaton.frameInterval + 0.0001)
            } else {
                XCTAssertEqual(duration, Chaton.frameInterval, accuracy: 0.0001)
            }
        }
        XCTAssertGreaterThan(Set(pauses.map { Int(($0 * 1_000).rounded()) }).count, 1)
        XCTAssertGreaterThan(plan.reloadAfter.timeIntervalSince(t0), 10 * 60)
        XCTAssertLessThan(plan.reloadAfter, t0.addingTimeInterval(ChatonWidgetPlan.timelineDuration))
    }

    func testReloadDuringSleepKeepsTheSameWakeUpTime() throws {
        let original = ChatonWidgetPlan.make(now: t0, mode: .always, snapshot: nil)
        let reloadDate = t0.addingTimeInterval(2)
        let reloaded = ChatonWidgetPlan.make(now: reloadDate, mode: .always, snapshot: nil)
        XCTAssertEqual(reloaded.entries.first?.frame, Chaton.restFrame)
        XCTAssertEqual(reloaded.entries.first?.date, reloadDate)
        let originalWake = try XCTUnwrap(original.entries.dropFirst().first)
        let reloadedWake = try XCTUnwrap(reloaded.entries.dropFirst().first)
        XCTAssertEqual(originalWake, reloadedWake, "Reloading must not restart the pause.")
    }

    func testReloadDuringMovementKeepsTheCurrentPoseAndNextChange() throws {
        let original = ChatonWidgetPlan.make(now: t0, mode: .always, snapshot: nil)
        let moving = try XCTUnwrap(original.entries.first { $0.frame == 22 })
        let reloadDate = moving.date.addingTimeInterval(0.05)
        let reloaded = ChatonWidgetPlan.make(now: reloadDate, mode: .always, snapshot: nil)
        XCTAssertEqual(reloaded.entries.first?.frame, moving.frame)
        let next = try XCTUnwrap(original.entries.first { $0.date > reloadDate })
        XCTAssertEqual(reloaded.entries.dropFirst().first, next)
    }

    func testSessionExpirationDuringSleepFreezesAtTheExactDeadline() {
        let plan = ChatonWidgetPlan.make(now: t0, mode: .session,
                                         snapshot: snapshot(now: t0, expiresIn: 2))
        XCTAssertEqual(plan.entries, [
            ChatonWidgetFrame(date: t0, frame: Chaton.restFrame, active: true),
            ChatonWidgetFrame(date: t0.addingTimeInterval(2), frame: Chaton.restFrame,
                              active: false),
        ])
    }

    func testSessionExpirationDuringMovementFreezesWithoutFurtherFrames() {
        let wake = ChatonAnimation.pose(at: t0).nextChange
        let now = wake.addingTimeInterval(0.03)
        let expires = now.addingTimeInterval(0.4)
        let plan = ChatonWidgetPlan.make(now: now, mode: .session,
                                         snapshot: snapshot(now: now, expiresIn: 0.4))
        XCTAssertEqual(plan.entries.first?.frame, 15)
        XCTAssertTrue(plan.entries.dropLast().allSatisfy { $0.active })
        XCTAssertEqual(plan.entries.last,
                       ChatonWidgetFrame(date: expires, frame: Chaton.restFrame, active: false))
    }

    func testAlwaysModeExpiresActivityDuringPauseButKeepsMoving() {
        let plan = ChatonWidgetPlan.make(now: t0, mode: .always,
                                         snapshot: snapshot(now: t0, expiresIn: 2))
        let expiry = t0.addingTimeInterval(2)
        XCTAssertEqual(plan.entries.first { $0.date == expiry },
                       ChatonWidgetFrame(date: expiry, frame: Chaton.restFrame, active: false))
        XCTAssertTrue(plan.entries.filter { $0.date >= expiry }.allSatisfy { !$0.active })
        XCTAssertTrue(plan.entries.contains { $0.date > expiry && $0.frame != Chaton.restFrame })
    }

    func testStaleSnapshotStopsSessionEvenWithLaterActivityExpiration() {
        let plan = ChatonWidgetPlan.make(now: t0, mode: .session,
                                         snapshot: snapshot(now: t0, expiresIn: 1_000))
        XCTAssertEqual(plan.entries.last,
                       ChatonWidgetFrame(
                           date: t0.addingTimeInterval(MiaouWidgetSnapshot.staleInterval),
                           frame: Chaton.restFrame, active: false))
    }

    func testMonthBoundaryStopsSession() throws {
        let boundary = try XCTUnwrap(Calendar.current.dateInterval(of: .month, for: t0)?.end)
        let now = boundary.addingTimeInterval(-2)
        let plan = ChatonWidgetPlan.make(now: now, mode: .session,
                                         snapshot: snapshot(now: now, expiresIn: 60))
        XCTAssertEqual(plan.entries.last,
                       ChatonWidgetFrame(date: boundary, frame: Chaton.restFrame, active: false))
    }

    func testSessionModeWithoutActivityRests() {
        for value in [nil, snapshot(now: t0), snapshot(now: t0, expiresIn: -1)] {
            let plan = ChatonWidgetPlan.make(now: t0, mode: .session, snapshot: value)
            XCTAssertEqual(plan.entries, [
                ChatonWidgetFrame(date: t0, frame: Chaton.restFrame, active: false),
            ])
            XCTAssertEqual(plan.reloadAfter, t0.addingTimeInterval(60))
        }
    }
}
