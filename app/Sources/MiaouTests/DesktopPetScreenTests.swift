import AppKit
import XCTest
@testable import Miaou

final class DesktopPetScreenTests: XCTestCase {
    private let builtIn = DesktopPetDisplay(
        id: 1, isBuiltIn: true,
        frame: CGRect(x: -1512, y: -200, width: 1512, height: 950),
        visibleFrame: CGRect(x: -1512, y: -168, width: 1512, height: 918),
        backingScaleFactor: 2
    )
    private let external = DesktopPetDisplay(
        id: 2, isBuiltIn: false,
        frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 0, y: 25, width: 2560, height: 1415),
        backingScaleFactor: 1
    )
    private let otherExternal = DesktopPetDisplay(
        id: 3, isBuiltIn: false,
        frame: CGRect(x: 2560, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 2560, y: 0, width: 1920, height: 1080),
        backingScaleFactor: 1
    )

    func testPrimaryUsesTheMacOSPrimaryIDRegardlessOfScreenOrder() {
        for screens in [[builtIn, external], [external, builtIn]] {
            XCTAssertEqual(DesktopPetScreenMode.primary.displays(
                from: screens, primaryID: external.id
            ).map(\.id), [external.id])
        }
    }

    func testBuiltInSelectsTheIntegratedDisplayWhenPrimaryIsExternal() {
        let selected = DesktopPetScreenMode.builtIn.displays(
            from: [external, otherExternal, builtIn], primaryID: external.id
        )
        XCTAssertEqual(selected.map(\.id), [builtIn.id])
        XCTAssertEqual(selected.first?.visibleFrame, builtIn.visibleFrame)
        XCTAssertEqual(selected.first?.backingScaleFactor, 2)
    }

    func testWalkAreaSitsOnThePhysicalBottomEdgeOfEveryScreen() {
        // The visible frame can start higher (menu bar, Dock), but the cat
        // must walk on the physical bottom edge, identically on every
        // screen regardless of DPI.
        for display in [builtIn, external, otherExternal] {
            XCTAssertEqual(display.walkArea.minY, display.frame.minY)
            XCTAssertEqual(display.walkArea.minX, display.frame.minX + 8)
            XCTAssertEqual(display.walkArea.maxX, display.frame.maxX - 8)
        }
        // The fixtures really differ in visible vs physical bottom edge.
        XCTAssertNotEqual(builtIn.visibleFrame.minY, builtIn.frame.minY)
        XCTAssertNotEqual(external.visibleFrame.minY, external.frame.minY)
    }

    func testBothIncludesOnlyPrimaryAndBuiltIn() {
        XCTAssertEqual(DesktopPetScreenMode.both.displays(
            from: [otherExternal, builtIn, external], primaryID: external.id
        ).map(\.id), [external.id, builtIn.id])
    }

    func testBothDoesNotDuplicateAnIntegratedPrimaryDisplay() {
        XCTAssertEqual(DesktopPetScreenMode.both.displays(
            from: [external, builtIn], primaryID: builtIn.id
        ).map(\.id), [builtIn.id])
    }

    func testUnavailableBuiltInFallsBackToPrimaryWithoutDuplicatingIt() {
        for mode in DesktopPetScreenMode.allCases {
            XCTAssertEqual(mode.displays(
                from: [otherExternal, external], primaryID: external.id
            ).map(\.id), [external.id])
        }
    }

    func testDisconnectingAndReconnectingDisplaysResolvesTheSamePreference() {
        let mode = DesktopPetScreenMode.both
        XCTAssertEqual(mode.displays(from: [external, builtIn], primaryID: external.id)
            .map(\.id), [external.id, builtIn.id])
        XCTAssertEqual(mode.displays(from: [builtIn], primaryID: builtIn.id)
            .map(\.id), [builtIn.id])
        XCTAssertEqual(mode.displays(from: [external, builtIn], primaryID: external.id)
            .map(\.id), [external.id, builtIn.id])
        XCTAssertEqual(mode.displays(from: [external, builtIn], primaryID: builtIn.id)
            .map(\.id), [builtIn.id])
    }

    func testScreenTransitionsHandleAnEmptyOrTemporarilyMissingPrimary() {
        for mode in DesktopPetScreenMode.allCases {
            XCTAssertTrue(mode.displays(from: [], primaryID: 0).isEmpty)
            XCTAssertEqual(mode.displays(from: [external], primaryID: 0).map(\.id), [external.id])
        }
    }

    func testBubblesStayWithTheirCatOnDisplaysInEveryDirection() {
        let screens = [
            external.visibleFrame, builtIn.visibleFrame, otherExternal.visibleFrame,
            CGRect(x: 0, y: 1440, width: 1920, height: 1080),
            CGRect(x: 0, y: -1080, width: 1920, height: 1080),
        ]
        for screen in screens {
            for size in DesktopPetSize.allCases {
                for pet in BarPet.allCases {
                    let dimensions = size.dimensions(for: pet)
                    for x in [screen.minX + 8, screen.maxX - dimensions.width - 8] {
                        let cat = CGRect(origin: CGPoint(x: x, y: screen.minY),
                                         size: dimensions)
                        let bubble = DesktopPetSpeechView.frame(above: cat, within: screen)
                        XCTAssertTrue(screen.contains(bubble))
                        XCTAssertGreaterThan(bubble.minY, cat.maxY)
                        XCTAssertTrue((bubble.minX...bubble.maxX).contains(cat.midX))
                    }
                }
            }
        }
    }
}
