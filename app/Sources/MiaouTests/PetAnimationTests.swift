import XCTest
@testable import Miaou

final class PetAnimationTests: XCTestCase {
    func testWakeUpAndCycleWrapKeepTheOriginalFrameOrder() {
        for pet in BarPet.allCases {
            var date = Date(timeIntervalSinceReferenceDate: 0)
            var expected = pet.restFrame
            for _ in 0..<(pet.frameCount - 1) * 65 {
                let pose = PetAnimation.pose(at: date, pet: pet)
                XCTAssertEqual(pose.frame, expected, "\(pet)")
                XCTAssertGreaterThan(pose.nextChange, date)
                XCTAssertEqual(
                    PetAnimation.pose(at: pose.nextChange.addingTimeInterval(-0.001), pet: pet).frame,
                    expected, "The pose must be held until the next change.")
                date = pose.nextChange
                expected = pet.nextFrame(after: expected)
            }
        }
    }

    func testWidgetPosesMatchTheClockUsedByTheMenuBanner() {
        // A realistic date and a reload midway through a frame must use
        // the same phase as the app, independent of provider invocation.
        let now = Date(timeIntervalSince1970: 1_800_000_000.037)
        for pet in BarPet.allCases {
            let plan = ChatonWidgetPlan.make(now: now, mode: .always, snapshot: nil, pet: pet)
            for entry in plan.entries {
                XCTAssertEqual(entry.frame, PetAnimation.pose(at: entry.date, pet: pet).frame)
            }
            for (current, next) in zip(plan.entries, plan.entries.dropFirst()) {
                let between = current.date.addingTimeInterval(
                    next.date.timeIntervalSince(current.date) / 2)
                XCTAssertEqual(PetAnimation.pose(at: between, pet: pet).frame, current.frame)
            }
        }
    }

    func testDatesBeforeTheClockEpochRemainValid() {
        let date = Date(timeIntervalSinceReferenceDate: -100)
        for pet in BarPet.allCases {
            let pose = PetAnimation.pose(at: date, pet: pet)
            XCTAssertTrue((1..<pet.frameCount).contains(pose.frame))
            XCTAssertGreaterThan(pose.nextChange, date)
        }
    }

    func testSwitchingAnActiveBannerSamplesTheNewPetsClock() {
        let animator = PetAnimator(restsInLoop: true)
        defer { animator.setActive(false) }
        animator.setActive(true)
        for pet in [BarPet.chonk, .chaton, .chonk] {
            let before = PetAnimation.pose(at: Date(), pet: pet).frame
            animator.setPet(pet)
            let after = PetAnimation.pose(at: Date(), pet: pet).frame
            XCTAssertEqual(animator.pet, pet)
            XCTAssertTrue([before, after].contains(animator.frame),
                          "Switching glyph must discard the old timer and sample the new clock.")
        }
        animator.setActive(false)
        XCTAssertEqual(animator.frame, BarPet.chonk.restFrame)
        animator.setPet(.chaton)
        XCTAssertEqual(animator.frame, BarPet.chaton.restFrame)
    }
}
