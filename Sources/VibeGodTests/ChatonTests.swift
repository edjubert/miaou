import XCTest
@testable import VibeGod

final class ChatonTests: XCTestCase {
    private func key(_ c: (col: Int, row: Int)) -> Int {
        c.col * 32 + c.row
    }

    private func set(_ cells: [(col: Int, row: Int)]) -> Set<Int> {
        Set(cells.map(key))
    }

    func testAnimationFrameCount() {
        // Reference pose + 26 transitions.
        XCTAssertEqual(Chaton.frames.count, Chaton.transitions.count + 1)
        XCTAssertEqual(Chaton.frames.count, 27)
    }

    func testFirstFrameIsReferencePose() {
        XCTAssertEqual(set(Chaton.frames[0]), set(Chaton.cells))
    }

    func testFramesStayInGrid() {
        for (i, frame) in Chaton.frames.enumerated() {
            for c in frame {
                XCTAssertTrue((0..<Chaton.gridW).contains(c.col), "frame \(i) col \(c.col)")
                XCTAssertTrue((0..<Chaton.gridH).contains(c.row), "frame \(i) row \(c.row)")
            }
            // A transition never adds a cell twice to the same frame.
            XCTAssertEqual(frame.count, set(frame).count, "frame \(i) has duplicates")
        }
    }

    func testAnimationIsPeriodic() {
        // The rest state plus the first transition must give the second
        // state: the cycle loops without ever replaying state 0.
        let rest = set(Chaton.frames[Chaton.frames.count - 1])
        let loop = rest
            .subtracting(set(Chaton.transitions[0].remove))
            .union(set(Chaton.transitions[0].add))
        XCTAssertEqual(loop, set(Chaton.frames[1]))
    }

    func testCycleWrapsAfterLastState() {
        // Periodic loop on states 1...26: state 0 is never revisited.
        XCTAssertEqual(ChatonAnimator.nextFrame(after: 26), 1)
        XCTAssertEqual(ChatonAnimator.nextFrame(after: 25), 26)
        XCTAssertEqual(ChatonAnimator.nextFrame(after: 14), 15)
    }

    func testRestFrameIsValidCycleState() {
        let rest = ChatonAnimator.restFrame
        XCTAssertGreaterThan(rest, 0)
        XCTAssertLessThan(rest, Chaton.frames.count - 1)
        XCTAssertFalse(Chaton.frames[rest].isEmpty)
    }
}
