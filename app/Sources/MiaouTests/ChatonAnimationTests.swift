import XCTest
@testable import Miaou

final class ChatonAnimationTests: XCTestCase {
    func testWakeUpAndCycleWrapKeepTheOriginalFrameOrder() {
        var date = Date(timeIntervalSinceReferenceDate: 0)
        var expected = Chaton.restFrame
        for _ in 0..<26 * 65 {
            let pose = ChatonAnimation.pose(at: date)
            XCTAssertEqual(pose.frame, expected)
            XCTAssertGreaterThan(pose.nextChange, date)
            XCTAssertEqual(ChatonAnimation.pose(at: pose.nextChange.addingTimeInterval(-0.001)).frame,
                           expected, "The pose must be held until the next change.")
            date = pose.nextChange
            expected = Chaton.nextFrame(after: expected)
        }
    }

    func testWidgetPosesMatchTheClockUsedByTheMenuBanner() {
        // A realistic date and a reload midway through a frame must use
        // the same phase as the app, independent of provider invocation.
        let now = Date(timeIntervalSince1970: 1_800_000_000.037)
        let plan = ChatonWidgetPlan.make(now: now, mode: .always, snapshot: nil)
        for entry in plan.entries {
            XCTAssertEqual(entry.frame, ChatonAnimation.pose(at: entry.date).frame)
        }
        for (current, next) in zip(plan.entries, plan.entries.dropFirst()) {
            let between = current.date.addingTimeInterval(
                next.date.timeIntervalSince(current.date) / 2)
            XCTAssertEqual(ChatonAnimation.pose(at: between).frame, current.frame)
        }
    }

    func testDatesBeforeTheClockEpochRemainValid() {
        let date = Date(timeIntervalSinceReferenceDate: -100)
        let pose = ChatonAnimation.pose(at: date)
        XCTAssertTrue((1...26).contains(pose.frame))
        XCTAssertGreaterThan(pose.nextChange, date)
    }
}
