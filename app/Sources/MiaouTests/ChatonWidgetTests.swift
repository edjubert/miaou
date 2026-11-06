import XCTest
@testable import Miaou

final class ChatonWidgetTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func XCTAssertEqualDate(_ a: Date, _ b: Date, accuracy: Double = 0.0001,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.timeIntervalSince1970, b.timeIntervalSince1970, accuracy: accuracy,
                       file: file, line: line)
    }

    private func snapshot(now: Date, expiresIn: TimeInterval? = nil) -> MiaouWidgetSnapshot {
        MiaouWidgetSnapshot(
            updatedAt: now, month: MiaouWidgetSnapshot.monthKey(now), currency: "€",
            language: "en", monthCost: 1, budgetCost: 10, monthTokens: 100,
            todayCost: 1, todayTokens: 10, todayRequests: 1,
            activityExpiresAt: expiresIn.map { now.addingTimeInterval($0) }, daily: [])
    }

    func testAlwaysModeLoopsOneFullCycleThenReloads() {
        let plan = ChatonWidgetPlan.make(now: t0, mode: .always, snapshot: nil)
        XCTAssertEqual(plan.entries.count, 26)
        for (index, entry) in plan.entries.enumerated() {
            XCTAssertEqualDate(entry.date, t0.addingTimeInterval(TimeInterval(index) * Chaton.frameInterval))
            XCTAssertEqual(entry.frame, index + 1, "The cycle runs frames 1...26 in order.")
            XCTAssertFalse(entry.active)
        }
        XCTAssertEqualDate(plan.reloadAfter, t0.addingTimeInterval(ChatonWidgetPlan.cycleDuration))
    }

    func testSessionModeAnimatesWhileActiveThenFreezesAtExpiration() {
        let plan = ChatonWidgetPlan.make(now: t0, mode: .session,
                                         snapshot: snapshot(now: t0, expiresIn: 2))
        // Frames advance every 0.16 s until the activity expires at t0 + 2.
        XCTAssertEqual(plan.entries.count, 14)
        for (index, entry) in plan.entries.prefix(13).enumerated() {
            XCTAssertEqualDate(entry.date, t0.addingTimeInterval(TimeInterval(index) * Chaton.frameInterval))
            XCTAssertEqual(entry.frame, index + 1)
            XCTAssertTrue(entry.active)
        }
        let freeze = plan.entries[13]
        XCTAssertEqualDate(freeze.date, t0.addingTimeInterval(2))
        XCTAssertEqual(freeze.frame, Chaton.restFrame)
        XCTAssertFalse(freeze.active)
        XCTAssertEqualDate(plan.reloadAfter, t0.addingTimeInterval(2 + Chaton.frameInterval))
    }

    func testSessionModeActiveBeyondOneCycleKeepsAnimating() {
        let plan = ChatonWidgetPlan.make(now: t0, mode: .session,
                                         snapshot: snapshot(now: t0, expiresIn: 10))
        XCTAssertEqual(plan.entries.count, 26)
        XCTAssertTrue(plan.entries.allSatisfy { $0.active })
        XCTAssertTrue(plan.entries.allSatisfy { (1...26).contains($0.frame) })
        XCTAssertEqualDate(plan.reloadAfter, t0.addingTimeInterval(ChatonWidgetPlan.cycleDuration))
    }

    func testSessionModeWithoutActivityRestsUntilSnapshotDeadlines() {
        let plan = ChatonWidgetPlan.make(now: t0, mode: .session, snapshot: snapshot(now: t0))
        XCTAssertFalse(plan.entries.isEmpty)
        XCTAssertEqual(plan.entries.first?.date, t0)
        XCTAssertTrue(plan.entries.allSatisfy { $0.frame == Chaton.restFrame && !$0.active })
        let wakeups = plan.entries.dropFirst().map(\.date)
        XCTAssertTrue(wakeups.allSatisfy { $0 > t0 })
        XCTAssertTrue(wakeups.contains {
            abs($0.timeIntervalSince(t0) - MiaouWidgetSnapshot.staleInterval) < 0.0001
        }, "The widget wakes up when the snapshot goes stale.")
        XCTAssertEqualDate(plan.reloadAfter, t0.addingTimeInterval(60))
    }

    func testSessionModeWithoutSnapshotRests() {
        let plan = ChatonWidgetPlan.make(now: t0, mode: .session, snapshot: nil)
        XCTAssertEqual(plan.entries.count, 1)
        XCTAssertEqual(plan.entries[0].frame, Chaton.restFrame)
        XCTAssertFalse(plan.entries[0].active)
    }
}
