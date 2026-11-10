import AppKit
import XCTest
@testable import Miaou

final class DesktopPetTests: XCTestCase {
    private let petSize = CGSize(width: 100, height: 80)

    private func advance(_ motion: inout DesktopPetMotion, at time: TimeInterval,
                         elapsed: TimeInterval = 0.1, limits: ClosedRange<CGFloat> = 0...400,
                         pointerOnLeft: Bool? = nil, autonomous: Bool = false,
                         sleepMode: DesktopPetSleepMode = .edge) {
        motion.advance(at: time, elapsed: elapsed, within: limits,
                       pointerOnLeft: pointerOnLeft, petSize: petSize,
                       autonomous: autonomous, sleepMode: sleepMode)
    }

    func testSpeedDefaultsToTheWalkingSpeedAndClampsToASaneRange() {
        let defaults = UserDefaults(suiteName: "miaou-test-speed")!
        defaults.removeObject(forKey: "desktopPetSpeed")
        XCTAssertEqual(DesktopPetController.speed(defaults), DesktopPetMotion.walkingSpeed)
        defaults.set(80.0, forKey: "desktopPetSpeed")
        XCTAssertEqual(DesktopPetController.speed(defaults), 80)
        defaults.set(-50.0, forKey: "desktopPetSpeed")
        XCTAssertEqual(DesktopPetController.speed(defaults), 1)
        defaults.set(10_000.0, forKey: "desktopPetSpeed")
        XCTAssertEqual(DesktopPetController.speed(defaults), 500)
        defaults.removeObject(forKey: "desktopPetSpeed")
    }

    func testMotionSpeedChangesTheDistanceWalkedPerTick() {
        var slow = DesktopPetMotion()
        slow.place(at: 100)
        slow.speed = 10
        advance(&slow, at: 1, autonomous: true)
        var fast = DesktopPetMotion()
        fast.place(at: 100)
        fast.speed = 100
        advance(&fast, at: 1, autonomous: true)
        XCTAssertEqual(slow.x, 101, accuracy: 0.001)
        XCTAssertEqual(fast.x, 110, accuracy: 0.001)
    }

    func testBottomOffsetIsPerScreenKindWithLegacyGlobalFallback() {
        let defaults = UserDefaults(suiteName: "miaou-test-bottom-offset")!
        for key in ["desktopPetBottomOffsetBuiltIn", "desktopPetBottomOffsetExternal",
                    "desktopPetBottomOffset"] {
            defaults.removeObject(forKey: key)
        }
        XCTAssertEqual(DesktopPetController.bottomOffset(defaults, isBuiltIn: true), 0)
        XCTAssertEqual(DesktopPetController.bottomOffset(defaults, isBuiltIn: false), 0)
        defaults.set(-7.5, forKey: "desktopPetBottomOffsetBuiltIn")
        defaults.set(3.0, forKey: "desktopPetBottomOffsetExternal")
        XCTAssertEqual(DesktopPetController.bottomOffset(defaults, isBuiltIn: true), -7.5)
        XCTAssertEqual(DesktopPetController.bottomOffset(defaults, isBuiltIn: false), 3)
        // Legacy global key applies to both kinds when no per-kind key.
        defaults.removeObject(forKey: "desktopPetBottomOffsetBuiltIn")
        defaults.removeObject(forKey: "desktopPetBottomOffsetExternal")
        defaults.set(2.0, forKey: "desktopPetBottomOffset")
        XCTAssertEqual(DesktopPetController.bottomOffset(defaults, isBuiltIn: true), 2)
        XCTAssertEqual(DesktopPetController.bottomOffset(defaults, isBuiltIn: false), 2)
        // A per-kind key wins over the legacy global one.
        defaults.set(-1.0, forKey: "desktopPetBottomOffsetExternal")
        XCTAssertEqual(DesktopPetController.bottomOffset(defaults, isBuiltIn: false), -1)
        XCTAssertEqual(DesktopPetController.bottomOffset(defaults, isBuiltIn: true), 2)
        for key in ["desktopPetBottomOffsetBuiltIn", "desktopPetBottomOffsetExternal",
                    "desktopPetBottomOffset"] {
            defaults.removeObject(forKey: key)
        }
    }

    func testAutonomousWalkingFollowsAnimationModeAndLiveSessions() {
        for mode in ChatonAnimationMode.allCases {
            for live in [false, true] {
                XCTAssertEqual(
                    DesktopPetController.autonomous(animationMode: mode, live: live),
                    mode == .always || live)
            }
        }
    }

    func testColorModeFollowsTheSelectedModeLiveSessionsAndMovement() {
        for mode in ChatonColorMode.allCases {
            for live in [false, true] {
                for resting in [false, true] {
                    let expected: Bool
                    switch mode {
                    case .color: expected = true
                    case .grayscale: expected = false
                    // Session mode: colored while a session is live, and
                    // while the cat moves (e.g. a hover-triggered walk).
                    case .session: expected = live || !resting
                    }
                    XCTAssertEqual(
                        DesktopPetController.colored(mode: mode, live: live, resting: resting),
                        expected)
                }
            }
        }
    }

    func testColorModeMigratesTheLegacyBooleanPreference() {
        let defaults = UserDefaults(suiteName: "miaou-test-color-mode")!
        defaults.removeObject(forKey: "desktopPetColorMode")
        defaults.removeObject(forKey: "desktopPetColorDuringSession")
        XCTAssertEqual(DesktopPetController.colorMode(defaults), .session)
        defaults.set(false, forKey: "desktopPetColorDuringSession")
        XCTAssertEqual(DesktopPetController.colorMode(defaults), .grayscale)
        defaults.set(true, forKey: "desktopPetColorDuringSession")
        XCTAssertEqual(DesktopPetController.colorMode(defaults), .color)
        defaults.set("grayscale", forKey: "desktopPetColorMode")
        XCTAssertEqual(DesktopPetController.colorMode(defaults), .grayscale)
        defaults.set("bogus", forKey: "desktopPetColorMode")
        XCTAssertEqual(DesktopPetController.colorMode(defaults), .session)
        defaults.removeObject(forKey: "desktopPetColorMode")
        defaults.removeObject(forKey: "desktopPetColorDuringSession")
    }

    func testDesktopPetChoiceIsIndependentOfTheBarIcon() {
        let defaults = UserDefaults(suiteName: "miaou-test-pet-choice")!
        defaults.removeObject(forKey: "desktopPetPet")
        defaults.removeObject(forKey: "barIcon")
        XCTAssertEqual(DesktopPetController.pet(defaults), .chaton)
        defaults.set("chonk", forKey: "desktopPetPet")
        XCTAssertEqual(DesktopPetController.pet(defaults), .chonk)
        // The bar icon no longer drives the desktop pet.
        defaults.set("logo", forKey: "barIcon")
        XCTAssertEqual(DesktopPetController.pet(defaults), .chonk)
        defaults.set("chaton", forKey: "desktopPetPet")
        defaults.set("chonk", forKey: "barIcon")
        XCTAssertEqual(DesktopPetController.pet(defaults), .chaton)
        defaults.set("bogus", forKey: "desktopPetPet")
        XCTAssertEqual(DesktopPetController.pet(defaults), .chaton)
        defaults.removeObject(forKey: "desktopPetPet")
        defaults.removeObject(forKey: "barIcon")
    }

    func testIdleCatNeverStartsWalkingOnItsOwn() {
        var motion = DesktopPetMotion()
        motion.place(at: 100)
        for time in [1.0, 60, 3600] {
            advance(&motion, at: time)
            XCTAssertEqual(motion.x, 100)
            XCTAssertTrue(motion.isResting)
            XCTAssertFalse(motion.isHopping)
            XCTAssertEqual(motion.verticalOffset, 0)
        }
    }

    func testRearrangingADisplayPreservesTheHopAndItsLandingTime() {
        for offset in [CGFloat(-1512), 2560] {
            var motion = DesktopPetMotion()
            motion.place(at: 100)
            advance(&motion, at: 1, pointerOnLeft: true)
            advance(&motion, at: 1.1)
            let height = motion.verticalOffset
            motion.translate(by: offset)
            XCTAssertEqual(motion.x, offset + 100 + 100 / 3, accuracy: 0.001)
            XCTAssertEqual(motion.verticalOffset, height)
            XCTAssertTrue(motion.isHopping)
            XCTAssertFalse(motion.isResting)
            advance(&motion, at: 1.15, limits: offset...(offset + 400))
            XCTAssertEqual(motion.x, offset + 150, accuracy: 0.001)
            XCTAssertEqual(motion.verticalOffset, petSize.height * 0.5, accuracy: 0.001)
            advance(&motion, at: 1.3, limits: offset...(offset + 400))
            XCTAssertEqual(motion.x, offset + 200, accuracy: 0.001)
            XCTAssertFalse(motion.isHopping)
            advance(&motion, at: 1.4, limits: offset...(offset + 400))
            XCTAssertEqual(motion.x, offset + 204.2, accuracy: 0.001)
        }
    }

    func testRearrangingADisplayPreservesTheWalkAcrossDisplays() {
        var motion = DesktopPetMotion()
        motion.place(at: 396)
        advance(&motion, at: 1, autonomous: true)
        XCTAssertEqual(motion.x, 400)
        XCTAssertFalse(motion.isResting)
        XCTAssertEqual(motion.direction, -1)
        motion.translate(by: -1512)
        advance(&motion, at: 40.999, limits: -1512 ... -1112, autonomous: true)
        XCTAssertFalse(motion.isResting)
        XCTAssertEqual(motion.x, -1116.2, accuracy: 0.001)
        advance(&motion, at: 41, limits: -1512 ... -1112, autonomous: true)
        XCTAssertFalse(motion.isResting)
        XCTAssertEqual(motion.x, -1120.4, accuracy: 0.001)
    }

    func testAResizedDisplayKeepsTheCurrentWalkWithinItsNewBounds() {
        var motion = DesktopPetMotion()
        motion.place(at: 300)
        advance(&motion, at: 1, autonomous: true)
        motion.translate(by: -1512)
        advance(&motion, at: 1.1, limits: -1512 ... -1312, autonomous: true)
        XCTAssertEqual(motion.x, -1312)
        XCTAssertFalse(motion.isResting)
        XCTAssertEqual(motion.direction, -1)
    }

    func testTwoDisplayPathsKeepIndependentHoverAndWalkingState() {
        var primary = DesktopPetMotion()
        var builtIn = DesktopPetMotion()
        primary.place(at: 196)
        builtIn.place(at: -100, direction: -1)
        advance(&primary, at: 1, limits: 0...200, autonomous: true)
        advance(&builtIn, at: 1, limits: -400 ... -100, autonomous: true)
        // Primary bounces at its right edge and keeps walking, while the
        // other display walks left.
        XCTAssertEqual(primary.x, 200)
        XCTAssertEqual(primary.direction, -1)
        XCTAssertFalse(primary.isResting)
        XCTAssertFalse(builtIn.isResting)
        XCTAssertEqual(builtIn.x, -104.2, accuracy: 0.001)
        advance(&builtIn, at: 2, limits: -400 ... -100,
                pointerOnLeft: true, autonomous: true)
        XCTAssertTrue(builtIn.isHopping)
        advance(&primary, at: 2, limits: 0...200, autonomous: true)
        XCTAssertFalse(primary.isHopping)
        XCTAssertFalse(primary.isResting)
        XCTAssertEqual(primary.x, 195.8, accuracy: 0.001)
        advance(&builtIn, at: 2.3, limits: -400 ... -100, autonomous: true)
        XCTAssertEqual(builtIn.x, -204.2, accuracy: 0.001)
        // Each path continues from its own position on later ticks.
        advance(&primary, at: 41, limits: 0...200, autonomous: true)
        advance(&builtIn, at: 41, limits: -400 ... -100, autonomous: true)
        XCTAssertFalse(primary.isResting)
        XCTAssertFalse(builtIn.isResting)
        XCTAssertEqual(primary.x, 191.6, accuracy: 0.001)
        XCTAssertEqual(builtIn.x, -208.4, accuracy: 0.001)
    }

    func testAutonomousWalkingBouncesAtBothEdgesWithoutResting() {
        for (start, direction) in [(CGFloat(196), CGFloat(1)), (4, -1)] {
            var motion = DesktopPetMotion()
            motion.place(at: start, direction: direction)
            advance(&motion, at: 1, limits: 0...200, autonomous: true)
            XCTAssertFalse(motion.isResting)
            XCTAssertEqual(motion.x, direction > 0 ? 200 : 0)
            XCTAssertEqual(motion.direction, -direction)
            for time in [1.1, 2, 60, 3600] {
                advance(&motion, at: time, limits: 0...200, autonomous: true)
                XCTAssertFalse(motion.isResting)
                XCTAssertTrue((0...200).contains(motion.x))
            }
        }
    }

    func testSleepModeDefaultsToEdgeAndReadsTheStoredValue() {
        let defaults = UserDefaults(suiteName: "miaou-test-sleep-mode")!
        defaults.removeObject(forKey: "desktopPetSleepMode")
        XCTAssertEqual(DesktopPetController.sleepMode(defaults), .edge)
        defaults.set("immediate", forKey: "desktopPetSleepMode")
        XCTAssertEqual(DesktopPetController.sleepMode(defaults), .immediate)
        defaults.set("bogus", forKey: "desktopPetSleepMode")
        XCTAssertEqual(DesktopPetController.sleepMode(defaults), .edge)
        defaults.removeObject(forKey: "desktopPetSleepMode")
    }

    func testImmediateSleepModeRestsWhereTheCatStandsWhenTheSessionEnds() {
        var motion = DesktopPetMotion()
        motion.place(at: 100)
        advance(&motion, at: 1, autonomous: true, sleepMode: .immediate)
        XCTAssertFalse(motion.isResting)
        XCTAssertEqual(motion.x, 104.2, accuracy: 0.001)
        // Session ends mid-walk: the cat sleeps immediately, not at an edge.
        advance(&motion, at: 1.1, sleepMode: .immediate)
        XCTAssertTrue(motion.isResting)
        XCTAssertEqual(motion.x, 104.2, accuracy: 0.001)
        advance(&motion, at: 3600, sleepMode: .immediate)
        XCTAssertTrue(motion.isResting)
        XCTAssertEqual(motion.x, 104.2, accuracy: 0.001)
    }

    func testEdgeSleepModeStillWalksToTheEdgeWhenTheSessionEnds() {
        var motion = DesktopPetMotion()
        motion.place(at: 190)
        advance(&motion, at: 1, limits: 0...200, autonomous: true, sleepMode: .edge)
        XCTAssertFalse(motion.isResting)
        advance(&motion, at: 1.1, limits: 0...200, sleepMode: .edge)
        XCTAssertFalse(motion.isResting)
        advance(&motion, at: 1.2, limits: 0...200, sleepMode: .edge)
        XCTAssertTrue(motion.isResting)
        XCTAssertEqual(motion.x, 200)
    }

    func testEdgeSleepModeSeeksTheNearestEdgeEvenTurningAround() {
        var motion = DesktopPetMotion()
        motion.place(at: 190, direction: -1)
        advance(&motion, at: 1, limits: 0...200, autonomous: true, sleepMode: .edge)
        // Walking left, away from the nearest (right) edge.
        XCTAssertEqual(motion.direction, -1)
        XCTAssertEqual(motion.x, 185.8, accuracy: 0.001)
        // Session ends: the cat turns around toward the nearest edge.
        advance(&motion, at: 1.1, limits: 0...200, sleepMode: .edge)
        XCTAssertEqual(motion.direction, 1)
        XCTAssertFalse(motion.isResting)
        for time in [1.2, 1.3, 1.4] {
            advance(&motion, at: time, limits: 0...200, sleepMode: .edge)
        }
        XCTAssertTrue(motion.isResting)
        XCTAssertEqual(motion.x, 200)
    }

    func testDisablingAutonomousWalkingFinishesTheTripThenStaysAsleep() {
        var motion = DesktopPetMotion()
        motion.place(at: 190)
        advance(&motion, at: 1, limits: 0...200, autonomous: true)
        XCTAssertFalse(motion.isResting)
        advance(&motion, at: 1.1, limits: 0...200)
        XCTAssertEqual(motion.x, 198.4, accuracy: 0.001)
        advance(&motion, at: 1.2, limits: 0...200)
        XCTAssertTrue(motion.isResting)
        advance(&motion, at: 3600, limits: 0...200)
        XCTAssertEqual(motion.x, 200)
        XCTAssertTrue(motion.isResting)
    }

    func testReenablingAutonomousWalkingWakesTheCatSleepingAtTheEdge() {
        var motion = DesktopPetMotion()
        motion.place(at: 100)
        advance(&motion, at: 1, limits: 0...200, pointerOnLeft: true)
        advance(&motion, at: 1.3, limits: 0...200)
        advance(&motion, at: 1.4, limits: 0...200)
        XCTAssertTrue(motion.isResting)
        XCTAssertEqual(motion.x, 200)
        advance(&motion, at: 2, limits: 0...200)
        XCTAssertTrue(motion.isResting)
        advance(&motion, at: 3, limits: 0...200, autonomous: true)
        XCTAssertFalse(motion.isResting)
        XCTAssertEqual(motion.x, 195.8, accuracy: 0.001)
    }

    func testHoverInterruptsAnAutonomousWalkAndFinishesAfterAnimationIsDisabled() {
        var motion = DesktopPetMotion()
        motion.place(at: 396)
        advance(&motion, at: 1, autonomous: true)
        XCTAssertFalse(motion.isResting)
        XCTAssertEqual(motion.x, 400)
        advance(&motion, at: 2, pointerOnLeft: true, autonomous: true)
        XCTAssertTrue(motion.isHopping)
        advance(&motion, at: 2.15)
        XCTAssertEqual(motion.verticalOffset, petSize.height * 0.5, accuracy: 0.001)
        advance(&motion, at: 2.3)
        XCTAssertEqual(motion.x, 300, accuracy: 0.001)
        XCTAssertFalse(motion.isHopping)
        // The session ended during the hop: the cat seeks the nearest edge
        // (the right one at 400), turning around.
        advance(&motion, at: 2.4)
        XCTAssertEqual(motion.direction, 1)
        XCTAssertEqual(motion.x, 304.2, accuracy: 0.001)
        XCTAssertFalse(motion.isResting)
    }

    func testAutonomousWalkingStaysAtRestWhenTheScreenHasNoRoom() {
        var motion = DesktopPetMotion()
        for time in [1.0, 60, 3600] {
            advance(&motion, at: time, limits: 0...0, autonomous: true)
            XCTAssertEqual(motion.x, 0)
            XCTAssertTrue(motion.isResting)
        }
    }

    func testHoverHopsAsideAwayFromThePointerWithAHalfHeightPeak() {
        for pointerOnLeft in [true, false] {
            var motion = DesktopPetMotion()
            motion.place(at: 200)
            advance(&motion, at: 1, pointerOnLeft: pointerOnLeft)
            XCTAssertEqual(motion.direction, pointerOnLeft ? 1 : -1)
            XCTAssertEqual(motion.x, 200)
            XCTAssertEqual(motion.verticalOffset, 0)
            XCTAssertFalse(motion.isResting)
            advance(&motion, at: 1.15)
            XCTAssertEqual(motion.x, pointerOnLeft ? 250 : 150, accuracy: 0.001)
            XCTAssertEqual(motion.verticalOffset, petSize.height * 0.5, accuracy: 0.001)
            advance(&motion, at: 1.3)
            XCTAssertEqual(motion.x, pointerOnLeft ? 300 : 100, accuracy: 0.001)
            XCTAssertEqual(motion.verticalOffset, 0, accuracy: 0.001)
            XCTAssertFalse(motion.isResting)
        }
    }

    func testHoverWakesASleepingCatAndHopsInwardAtEitherScreenEdge() {
        for start in [CGFloat(0), 400] {
            var motion = DesktopPetMotion()
            motion.place(at: start)
            advance(&motion, at: 20)
            XCTAssertTrue(motion.isResting)
            XCTAssertEqual(motion.x, start)
            advance(&motion, at: 21, pointerOnLeft: start == 400)
            XCTAssertFalse(motion.isResting)
            XCTAssertEqual(motion.direction, start == 400 ? -1 : 1)
            advance(&motion, at: 21.3)
            XCTAssertEqual(motion.x, start == 400 ? 300 : 100, accuracy: 0.001)
        }
    }

    func testChangingPoseDoesNotReverseOrRepeatTheHopWhileStillHovered() {
        var motion = DesktopPetMotion()
        motion.place(at: 100)
        advance(&motion, at: 1, pointerOnLeft: true)
        advance(&motion, at: 1.1, pointerOnLeft: false)
        XCTAssertEqual(motion.direction, 1)
        XCTAssertEqual(motion.x, 100 + 100 / 3, accuracy: 0.001)
        advance(&motion, at: 1.3, pointerOnLeft: false)
        advance(&motion, at: 1.4, pointerOnLeft: true)
        XCTAssertEqual(motion.x, 204.2, accuracy: 0.001)
        XCTAssertFalse(motion.isResting)
        XCTAssertFalse(motion.isHopping)
        XCTAssertEqual(motion.direction, 1)
    }

    func testLandingStartsWalkingUntilTheCornerThenRests() {
        var motion = DesktopPetMotion()
        motion.place(at: 100)
        advance(&motion, at: 1, limits: 0...210, pointerOnLeft: true)
        advance(&motion, at: 1.3, limits: 0...210)
        XCTAssertEqual(motion.x, 200)
        XCTAssertFalse(motion.isResting)
        XCTAssertFalse(motion.isHopping)
        advance(&motion, at: 1.4, limits: 0...210)
        XCTAssertEqual(motion.x, 204.2, accuracy: 0.001)
        XCTAssertFalse(motion.isResting)
        advance(&motion, at: 1.5, limits: 0...210)
        advance(&motion, at: 1.6, limits: 0...210)
        XCTAssertEqual(motion.x, 210)
        XCTAssertTrue(motion.isResting)
    }

    func testLeavingAndReenteringAfterLandingStartsAnotherHop() {
        var motion = DesktopPetMotion()
        motion.place(at: 100)
        advance(&motion, at: 1, pointerOnLeft: true)
        advance(&motion, at: 1.3)
        advance(&motion, at: 1.4, pointerOnLeft: false)
        XCTAssertFalse(motion.isResting)
        XCTAssertTrue(motion.isHopping)
        XCTAssertEqual(motion.direction, -1)
        advance(&motion, at: 1.7)
        XCTAssertEqual(motion.x, 100, accuracy: 0.001)
    }

    func testHopStaysWithinNarrowScreenLimits() {
        for start in [CGFloat(0), 20, 60] {
            for pointerOnLeft in [true, false] {
                var motion = DesktopPetMotion()
                motion.place(at: start)
                advance(&motion, at: 1, limits: 0...60, pointerOnLeft: pointerOnLeft)
                for time in [1.1, 1.2, 1.3, 1.4] {
                    advance(&motion, at: time, limits: 0...60)
                    XCTAssertTrue((0...60).contains(motion.x))
                    XCTAssertGreaterThanOrEqual(motion.verticalOffset, 0)
                    XCTAssertLessThanOrEqual(motion.verticalOffset, petSize.height * 0.5)
                }
                XCTAssertTrue(motion.isResting)
            }
        }
        var motion = DesktopPetMotion()
        advance(&motion, at: 1, limits: 0...0, pointerOnLeft: true)
        advance(&motion, at: 1.3, limits: 0...0)
        advance(&motion, at: 1.4, limits: 0...0)
        XCTAssertEqual(motion.x, 0)
        XCTAssertTrue(motion.isResting)
    }

    func testDelayedTicksLandAndResumeWithoutCrossingTheScreen() {
        var motion = DesktopPetMotion()
        motion.place(at: 100)
        advance(&motion, at: 1, pointerOnLeft: true)
        advance(&motion, at: 10, elapsed: 9)
        XCTAssertEqual(motion.x, 200)
        XCTAssertEqual(motion.verticalOffset, 0)
        XCTAssertFalse(motion.isResting)
        XCTAssertFalse(motion.isHopping)
        advance(&motion, at: 100, elapsed: 90)
        XCTAssertEqual(motion.x, 204.2, accuracy: 0.001)
        XCTAssertFalse(motion.isResting)
    }

    func testCornerRestLastsUntilAnotherHover() {
        var motion = DesktopPetMotion()
        motion.place(at: 100)
        advance(&motion, at: 1, limits: 0...200, pointerOnLeft: true)
        advance(&motion, at: 1.3, limits: 0...200)
        advance(&motion, at: 1.4, limits: 0...200)
        for time in [60.0, 3600] {
            advance(&motion, at: time, limits: 0...200)
            XCTAssertEqual(motion.x, 200)
            XCTAssertTrue(motion.isResting)
        }
        advance(&motion, at: 3601, limits: 0...200, pointerOnLeft: true)
        XCTAssertFalse(motion.isResting)
        XCTAssertTrue(motion.isHopping)
        XCTAssertEqual(motion.direction, -1)
    }

    func testGlassKeepsItsIntensityAndUsesTheMirroredPetSilhouette() {
        for pet in BarPet.allCases {
            let size = CGSize(width: 200, height: 200 * pet.barWindow.height / pet.barWindow.width)
            let view = DesktopPetView(pet: pet, size: size)
            view.show(frame: pet.restFrame, mirrored: false, glassTransparency: 0.12)
            XCTAssertFalse(view.subviews[0].isHidden)
            XCTAssertEqual(view.subviews[0].alphaValue, 0.88, accuracy: 0.001)
            XCTAssertFalse(view.subviews[1].isHidden, "The dot outline must remain visible.")
            XCTAssertFalse(view.containsPet(at: CGPoint(x: -10, y: -10)))
            let dots = pet == .chonk ? Chonk.dotRects(frame: pet.restFrame, size: size) :
                Chaton.dotRects(frame: pet.restFrame, size: size)
            let dot = dots[dots.count / 2].rect
            let point = CGPoint(x: dot.midX, y: size.height - dot.midY)
            XCTAssertTrue(view.containsPet(at: point))
            view.show(frame: pet.restFrame, mirrored: true, glassTransparency: 0.12)
            XCTAssertFalse(view.subviews[0].isHidden)
            XCTAssertEqual(view.subviews[0].alphaValue, 0.88, accuracy: 0.001)
            XCTAssertTrue(view.containsPet(at: CGPoint(x: size.width - point.x, y: point.y)))
            view.show(frame: view.walkFrame(at: 1), mirrored: true, colored: true,
                      glassTransparency: 0.12)
            XCTAssertFalse(view.subviews[0].isHidden)
            XCTAssertEqual(view.subviews[0].alphaValue, 0.88, accuracy: 0.001)
            view.show(frame: pet.restFrame, mirrored: false, glassTransparency: 1)
            XCTAssertTrue(view.subviews[0].isHidden, "Only the glass intensity setting hides the glass.")
        }
    }

    func testColorChangesRedrawTheDotsWithoutChangingThePose() throws {
        for pet in BarPet.allCases {
            let size = CGSize(width: 200, height: 200 * pet.barWindow.height / pet.barWindow.width)
            let view = DesktopPetView(pet: pet, size: size)
            let frame = view.walkFrame(at: 1)
            view.show(frame: frame, mirrored: false, colored: false)
            XCTAssertFalse(try hasColoredPixels(view.subviews[1]))
            view.show(frame: frame, mirrored: false, colored: true)
            XCTAssertTrue(try hasColoredPixels(view.subviews[1]))
            view.show(frame: frame, mirrored: false, colored: false)
            XCTAssertFalse(try hasColoredPixels(view.subviews[1]))
        }
    }

    private func hasColoredPixels(_ view: NSView) throws -> Bool {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        var hasOpaquePixels = false
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 3) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 3) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.5 else { continue }
                hasOpaquePixels = true
                if abs(color.redComponent - color.greenComponent) > 0.02 ||
                   abs(color.greenComponent - color.blueComponent) > 0.02 {
                    return true
                }
            }
        }
        XCTAssertTrue(hasOpaquePixels, "The dot outline must render in grayscale too.")
        return false
    }
}
