import AppKit
import XCTest
@testable import Miaou

final class DesktopPetTests: XCTestCase {
    private let petSize = CGSize(width: 100, height: 80)

    func testHoverHopsAsideAwayFromThePointerWithAHalfHeightPeak() {
        for pointerOnLeft in [true, false] {
            var motion = DesktopPetMotion()
            motion.place(at: 200)
            motion.advance(at: 1, elapsed: 0.1, within: 0...400,
                           pointerOnLeft: pointerOnLeft, petSize: petSize, wakeDuration: 5)
            XCTAssertEqual(motion.direction, pointerOnLeft ? 1 : -1)
            XCTAssertEqual(motion.x, 200)
            XCTAssertEqual(motion.verticalOffset, 0)
            motion.advance(at: 1.15, elapsed: 0.1, within: 0...400,
                           pointerOnLeft: nil, petSize: petSize, wakeDuration: 5)
            XCTAssertEqual(motion.x, pointerOnLeft ? 250 : 150, accuracy: 0.001)
            XCTAssertEqual(motion.verticalOffset, petSize.height * 0.5, accuracy: 0.001)
            motion.advance(at: 1.3, elapsed: 0.1, within: 0...400,
                           pointerOnLeft: nil, petSize: petSize, wakeDuration: 5)
            XCTAssertEqual(motion.x, pointerOnLeft ? 300 : 100, accuracy: 0.001)
            XCTAssertEqual(motion.verticalOffset, 0, accuracy: 0.001)
            XCTAssertNil(motion.restingSince)
        }
    }

    func testHoverWakesASleepingCatAndHopsInwardAtTheScreenEdge() {
        var motion = DesktopPetMotion()
        motion.place(at: 399)
        motion.advance(at: 1, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: nil, petSize: petSize, wakeDuration: 5, chooseSleep: { 60 })
        XCTAssertEqual(motion.restingSince, 1)
        motion.advance(at: 20, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: nil, petSize: petSize, wakeDuration: 5)
        XCTAssertEqual(motion.x, 400)
        motion.advance(at: 21, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: true, petSize: petSize, wakeDuration: 5)
        XCTAssertNil(motion.restingSince)
        XCTAssertEqual(motion.direction, -1)
        motion.advance(at: 21.3, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: nil, petSize: petSize, wakeDuration: 5)
        XCTAssertEqual(motion.x, 300, accuracy: 0.001)
    }

    func testChangingPoseDoesNotReverseOrRepeatTheHopWhileStillHovered() {
        var motion = DesktopPetMotion()
        motion.place(at: 100)
        motion.advance(at: 1, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: true, petSize: petSize, wakeDuration: 5)
        motion.advance(at: 1.1, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: false, petSize: petSize, wakeDuration: 5)
        XCTAssertEqual(motion.direction, 1)
        XCTAssertEqual(motion.x, 100 + 100 / 3, accuracy: 0.001)
        motion.advance(at: 1.6, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: false, petSize: petSize, wakeDuration: 5, chooseSleep: { 60 })
        motion.advance(at: 2, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: true, petSize: petSize, wakeDuration: 5)
        XCTAssertEqual(motion.x, 200)
        XCTAssertEqual(motion.restingSince ?? -1, 1.6, accuracy: 0.001)
        XCTAssertFalse(motion.isReactingToHover)
    }

    func testLandingHoldsPositionAndRestsAfter300Milliseconds() {
        var motion = DesktopPetMotion()
        motion.place(at: 100)
        motion.advance(at: 1, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: true, petSize: petSize, wakeDuration: 5)
        motion.advance(at: 1.3, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: nil, petSize: petSize, wakeDuration: 5)
        XCTAssertEqual(motion.x, 200)
        XCTAssertNil(motion.restingSince)
        motion.advance(at: 1.599, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: nil, petSize: petSize, wakeDuration: 5)
        XCTAssertEqual(motion.x, 200)
        XCTAssertEqual(motion.verticalOffset, 0)
        XCTAssertNil(motion.restingSince)
        motion.advance(at: 1.6, elapsed: 0.001, within: 0...400,
                       pointerOnLeft: nil, petSize: petSize, wakeDuration: 5, chooseSleep: { 60 })
        XCTAssertEqual(motion.x, 200)
        XCTAssertEqual(motion.restingSince ?? -1, 1.6, accuracy: 0.001)
        XCTAssertEqual(motion.sleepDuration, 60)
        XCTAssertFalse(motion.isReactingToHover)
    }

    func testLeavingAndReenteringAfterLandingStartsAnotherHop() {
        var motion = DesktopPetMotion()
        motion.place(at: 100)
        motion.advance(at: 1, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: true, petSize: petSize, wakeDuration: 5)
        motion.advance(at: 1.6, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: nil, petSize: petSize, wakeDuration: 5)
        motion.advance(at: 2, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: false, petSize: petSize, wakeDuration: 5)
        XCTAssertNil(motion.restingSince)
        XCTAssertTrue(motion.isReactingToHover)
        XCTAssertEqual(motion.direction, -1)
        motion.advance(at: 2.3, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: nil, petSize: petSize, wakeDuration: 5)
        XCTAssertEqual(motion.x, 100, accuracy: 0.001)
    }

    func testHopStaysWithinNarrowScreenLimits() {
        for start in [CGFloat(0), 20, 60] {
            for pointerOnLeft in [true, false] {
                var motion = DesktopPetMotion()
                motion.place(at: start)
                motion.advance(at: 1, elapsed: 0.1, within: 0...60,
                               pointerOnLeft: pointerOnLeft, petSize: petSize, wakeDuration: 5)
                for time in [1.1, 1.2, 1.3] {
                    motion.advance(at: time, elapsed: 0.1, within: 0...60,
                                   pointerOnLeft: nil, petSize: petSize, wakeDuration: 5)
                    XCTAssertTrue((0...60).contains(motion.x))
                    XCTAssertGreaterThanOrEqual(motion.verticalOffset, 0)
                    XCTAssertLessThanOrEqual(motion.verticalOffset, petSize.height * 0.5)
                }
            }
        }
    }

    func testDelayedTickAfterAHopKeepsTheActualLandingRestTime() {
        var motion = DesktopPetMotion()
        motion.place(at: 100)
        motion.advance(at: 1, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: true, petSize: petSize, wakeDuration: 5)
        motion.advance(at: 10, elapsed: 9, within: 0...400,
                       pointerOnLeft: nil, petSize: petSize, wakeDuration: 5, chooseSleep: { 60 })
        XCTAssertEqual(motion.x, 200)
        XCTAssertEqual(motion.verticalOffset, 0)
        XCTAssertEqual(motion.restingSince ?? -1, 1.6, accuracy: 0.001)
    }

    func testNormalRestHoldsPositionThroughSleepAndWakeAnimation() {
        var motion = DesktopPetMotion()
        motion.place(at: 399)
        motion.advance(at: 1, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: nil, petSize: petSize, wakeDuration: 5, chooseSleep: { 60 })
        motion.advance(at: 65.9, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: nil, petSize: petSize, wakeDuration: 5)
        XCTAssertEqual(motion.x, 400)
        motion.advance(at: 66, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: nil, petSize: petSize, wakeDuration: 5)
        XCTAssertNil(motion.restingSince)
        XCTAssertEqual(motion.x, 395.8, accuracy: 0.001)
    }

    func testDelayedTickCannotJumpAcrossTheScreen() {
        var motion = DesktopPetMotion()
        motion.place(at: 100)
        motion.advance(at: 100, elapsed: 90, within: 0...400,
                       pointerOnLeft: nil, petSize: petSize, wakeDuration: 5)
        XCTAssertEqual(motion.x, 104.2, accuracy: 0.001)
    }

    func testHoverHidesOnlyTheGlassAndUsesTheMirroredPetSilhouette() {
        for pet in BarPet.allCases {
            let size = CGSize(width: 200, height: 200 * pet.barWindow.height / pet.barWindow.width)
            let view = DesktopPetView(pet: pet, size: size)
            view.show(frame: pet.restFrame, mirrored: false, transparent: true)
            XCTAssertTrue(view.subviews[0].isHidden)
            XCTAssertFalse(view.subviews[1].isHidden, "The colored outline must remain visible.")
            XCTAssertFalse(view.containsPet(at: CGPoint(x: -10, y: -10)))
            let dots = pet == .chonk ? Chonk.dotRects(frame: pet.restFrame, size: size) :
                Chaton.dotRects(frame: pet.restFrame, size: size)
            let dot = dots[dots.count / 2].rect
            let point = CGPoint(x: dot.midX, y: size.height - dot.midY)
            XCTAssertTrue(view.containsPet(at: point))
            view.show(frame: pet.restFrame, mirrored: true, transparent: false)
            XCTAssertFalse(view.subviews[0].isHidden, "The glass must return after hovering.")
            XCTAssertTrue(view.containsPet(at: CGPoint(x: size.width - point.x, y: point.y)))
        }
    }
}
