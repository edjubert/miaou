import AppKit
import XCTest
@testable import Miaou

final class DesktopPetTests: XCTestCase {
    func testHoverEscapesAwayFromThePointerOnEitherSide() {
        for pointerOnLeft in [true, false] {
            var motion = DesktopPetMotion()
            motion.place(at: 100)
            motion.advance(at: 1, elapsed: 0.1, within: 0...400,
                           pointerOnLeft: pointerOnLeft, wakeDuration: 5)
            XCTAssertEqual(motion.direction, pointerOnLeft ? 1 : -1)
            XCTAssertEqual(motion.x, pointerOnLeft ? 118 : 82, accuracy: 0.001)
            XCTAssertTrue(motion.isFleeing(at: 1))
        }
    }

    func testHoverWakesASleepingCatAndEscapesInwardAtTheScreenEdge() {
        var motion = DesktopPetMotion()
        motion.place(at: 399)
        motion.advance(at: 1, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: nil, wakeDuration: 5, chooseSleep: { 60 })
        XCTAssertEqual(motion.restingSince, 1)
        motion.advance(at: 20, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: nil, wakeDuration: 5)
        XCTAssertEqual(motion.x, 400)
        motion.advance(at: 21, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: true, wakeDuration: 5)
        XCTAssertNil(motion.restingSince)
        XCTAssertEqual(motion.direction, -1)
        XCTAssertEqual(motion.x, 382, accuracy: 0.001)
    }

    func testChangingPoseDoesNotReverseTheEscapeWhileStillHovered() {
        var motion = DesktopPetMotion()
        motion.place(at: 100)
        motion.advance(at: 1, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: true, wakeDuration: 5)
        motion.advance(at: 1.1, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: false, wakeDuration: 5)
        XCTAssertEqual(motion.direction, 1)
        XCTAssertEqual(motion.x, 136, accuracy: 0.001)
    }

    func testEscapeTurnsAtTheEdgeWithoutSleepingThenResumesWalking() {
        var motion = DesktopPetMotion()
        motion.place(at: 399)
        motion.advance(at: 1, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: true, wakeDuration: 5)
        XCTAssertEqual(motion.x, 400)
        XCTAssertNil(motion.restingSince)
        motion.advance(at: 1.1, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: nil, wakeDuration: 5)
        XCTAssertEqual(motion.x, 382, accuracy: 0.001)
        motion.advance(at: 2.1, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: nil, wakeDuration: 5)
        XCTAssertFalse(motion.isFleeing(at: 2.1))
        XCTAssertEqual(motion.x, 377.8, accuracy: 0.001)
    }

    func testNormalRestHoldsPositionThroughSleepAndWakeAnimation() {
        var motion = DesktopPetMotion()
        motion.place(at: 399)
        motion.advance(at: 1, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: nil, wakeDuration: 5, chooseSleep: { 60 })
        motion.advance(at: 65.9, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: nil, wakeDuration: 5)
        XCTAssertEqual(motion.x, 400)
        motion.advance(at: 66, elapsed: 0.1, within: 0...400,
                       pointerOnLeft: nil, wakeDuration: 5)
        XCTAssertNil(motion.restingSince)
        XCTAssertEqual(motion.x, 395.8, accuracy: 0.001)
    }

    func testDelayedTickCannotJumpAcrossTheScreen() {
        var motion = DesktopPetMotion()
        motion.place(at: 100)
        motion.advance(at: 100, elapsed: 90, within: 0...400,
                       pointerOnLeft: nil, wakeDuration: 5)
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
