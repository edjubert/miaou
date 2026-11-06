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
        for pet in BarPet.allCases {
            let plan = ChatonWidgetPlan.make(now: t0, mode: .always, snapshot: nil, pet: pet)
            XCTAssertGreaterThan(plan.entries.count, (pet.frameCount - 1) * 10)
            XCTAssertLessThan(plan.entries.count, (pet.frameCount - 1) * 60,
                              "A sleeping pause needs one held pose, not frame-rate entries.")
            XCTAssertTrue(plan.entries.allSatisfy { !$0.active })
            var pauses: [TimeInterval] = []
            for (current, next) in zip(plan.entries, plan.entries.dropFirst()) {
                XCTAssertEqual(next.frame, pet.nextFrame(after: current.frame))
                let duration = next.date.timeIntervalSince(current.date)
                if current.frame == pet.restFrame {
                    pauses.append(duration - PetAnimation.frameInterval)
                    XCTAssertGreaterThanOrEqual(duration, 5 + PetAnimation.frameInterval - 0.0001)
                    XCTAssertLessThanOrEqual(duration, 20 + PetAnimation.frameInterval + 0.0001)
                } else {
                    XCTAssertEqual(duration, PetAnimation.frameInterval, accuracy: 0.0001)
                }
            }
            XCTAssertGreaterThan(Set(pauses.map { Int(($0 * 1_000).rounded()) }).count, 1)
            XCTAssertGreaterThan(plan.reloadAfter.timeIntervalSince(t0), 10 * 60)
            XCTAssertLessThan(plan.reloadAfter, t0.addingTimeInterval(ChatonWidgetPlan.timelineDuration))
        }
    }

    func testReloadDuringSleepKeepsTheSameWakeUpTime() throws {
        let original = ChatonWidgetPlan.make(now: t0, mode: .always, snapshot: nil)
        let reloadDate = t0.addingTimeInterval(2)
        let reloaded = ChatonWidgetPlan.make(now: reloadDate, mode: .always, snapshot: nil)
        XCTAssertEqual(reloaded.entries.first?.frame, BarPet.chaton.restFrame)
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
            ChatonWidgetFrame(date: t0, frame: BarPet.chaton.restFrame, active: true),
            ChatonWidgetFrame(date: t0.addingTimeInterval(2), frame: BarPet.chaton.restFrame,
                              active: false),
        ])
    }

    func testSessionExpirationDuringMovementFreezesWithoutFurtherFrames() {
        let wake = PetAnimation.pose(at: t0).nextChange
        let now = wake.addingTimeInterval(0.03)
        let expires = now.addingTimeInterval(0.4)
        let plan = ChatonWidgetPlan.make(now: now, mode: .session,
                                         snapshot: snapshot(now: now, expiresIn: 0.4))
        XCTAssertEqual(plan.entries.first?.frame, 15)
        XCTAssertTrue(plan.entries.dropLast().allSatisfy { $0.active })
        XCTAssertEqual(plan.entries.last,
                       ChatonWidgetFrame(date: expires, frame: BarPet.chaton.restFrame, active: false))
    }

    func testAlwaysModeExpiresActivityDuringPauseButKeepsMoving() {
        let plan = ChatonWidgetPlan.make(now: t0, mode: .always,
                                         snapshot: snapshot(now: t0, expiresIn: 2))
        let expiry = t0.addingTimeInterval(2)
        XCTAssertEqual(plan.entries.first { $0.date == expiry },
                       ChatonWidgetFrame(date: expiry, frame: BarPet.chaton.restFrame, active: false))
        XCTAssertTrue(plan.entries.filter { $0.date >= expiry }.allSatisfy { !$0.active })
        XCTAssertTrue(plan.entries.contains { $0.date > expiry && $0.frame != BarPet.chaton.restFrame })
    }

    func testStaleSnapshotStopsSessionEvenWithLaterActivityExpiration() {
        let plan = ChatonWidgetPlan.make(now: t0, mode: .session,
                                         snapshot: snapshot(now: t0, expiresIn: 1_000))
        XCTAssertEqual(plan.entries.last,
                       ChatonWidgetFrame(
                           date: t0.addingTimeInterval(MiaouWidgetSnapshot.staleInterval),
                           frame: BarPet.chaton.restFrame, active: false))
    }

    func testMonthBoundaryStopsSession() throws {
        let boundary = try XCTUnwrap(Calendar.current.dateInterval(of: .month, for: t0)?.end)
        let now = boundary.addingTimeInterval(-2)
        let plan = ChatonWidgetPlan.make(now: now, mode: .session,
                                         snapshot: snapshot(now: now, expiresIn: 60))
        XCTAssertEqual(plan.entries.last,
                       ChatonWidgetFrame(date: boundary, frame: BarPet.chaton.restFrame, active: false))
    }

    func testSessionModeWithoutActivityRests() {
        for pet in BarPet.allCases {
            for value in [nil, snapshot(now: t0), snapshot(now: t0, expiresIn: -1)] {
                let plan = ChatonWidgetPlan.make(now: t0, mode: .session, snapshot: value, pet: pet)
                XCTAssertEqual(plan.entries, [
                    ChatonWidgetFrame(date: t0, frame: pet.restFrame, active: false),
                ])
                XCTAssertEqual(plan.reloadAfter, t0.addingTimeInterval(60))
            }
        }
    }

    func testChonkReloadsKeepItsWakeUpTimeAndPose() throws {
        let original = ChatonWidgetPlan.make(now: t0, mode: .always, snapshot: nil, pet: .chonk)
        let wake = try XCTUnwrap(original.entries.dropFirst().first)
        XCTAssertEqual(wake.frame, 1)
        for reloadDate in [t0.addingTimeInterval(2), wake.date.addingTimeInterval(0.05)] {
            let reloaded = ChatonWidgetPlan.make(now: reloadDate, mode: .always,
                                                 snapshot: nil, pet: .chonk)
            XCTAssertEqual(reloaded.entries.first?.frame,
                           PetAnimation.pose(at: reloadDate, pet: .chonk).frame)
            XCTAssertEqual(reloaded.entries.dropFirst().first,
                           original.entries.first { $0.date > reloadDate })
        }
    }

    func testChonkSessionExpirationUsesItsOwnRestPose() {
        let wake = PetAnimation.pose(at: t0, pet: .chonk).nextChange
        for now in [t0, wake.addingTimeInterval(0.03)] {
            let plan = ChatonWidgetPlan.make(now: now, mode: .session,
                                             snapshot: snapshot(now: now, expiresIn: 0.4),
                                             pet: .chonk)
            XCTAssertEqual(plan.entries.last,
                           ChatonWidgetFrame(date: now.addingTimeInterval(0.4),
                                             frame: BarPet.chonk.restFrame, active: false))
            XCTAssertTrue(plan.entries.dropLast().allSatisfy { $0.active })
        }
    }

}
