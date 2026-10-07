import XCTest
@testable import Miaou

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

    func testSilhouetteFillsEnclosedHolesOnly() {
        var ring: [(col: Int, row: Int)] = []
        for i in 4...10 {
            ring.append((col: i, row: 4))
            ring.append((col: i, row: 10))
            ring.append((col: 4, row: i))
            ring.append((col: 10, row: i))
        }
        // A closed ring: the center becomes part of the silhouette.
        let closed = Set(Chaton.silhouette(ring).map(key))
        XCTAssertTrue(closed.contains(key((7, 7))))
        // An open ring (gap on the border): the flood fill reaches the
        // center, nothing is enclosed.
        var openRing = ring
        openRing.removeAll { $0.col == 7 && $0.row == 4 }
        let openSet = Set(Chaton.silhouette(openRing).map(key))
        XCTAssertFalse(openSet.contains(key((7, 7))))
        // Every animation silhouette covers its own frame's dots.
        for (i, pose) in Chaton.frames.enumerated() {
            let dots = Set(pose.map(key))
            let silKeys = Set(Chaton.silhouettes[i].map(key))
            XCTAssertTrue(silKeys.isSuperset(of: dots), "frame \(i)")
        }
        // Silhouettes are precomputed for every frame, in order.
        XCTAssertEqual(Chaton.silhouettes.count, Chaton.frames.count)
    }

    func testChatonColorModes() {
        // Always color.
        XCTAssertEqual(MistralIcon.palette(live: true, mode: .color), MistralLogo.brand)
        XCTAssertEqual(MistralIcon.palette(live: false, mode: .color), MistralLogo.brand)
        // Always grayscale.
        XCTAssertEqual(MistralIcon.palette(live: true, mode: .grayscale), MistralLogo.grayscale)
        XCTAssertEqual(MistralIcon.palette(live: false, mode: .grayscale), MistralLogo.grayscale)
        // By session.
        XCTAssertEqual(MistralIcon.palette(live: true, mode: .session), MistralLogo.brand)
        XCTAssertEqual(MistralIcon.palette(live: false, mode: .session), MistralLogo.grayscale)
    }
}
