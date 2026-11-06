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
        XCTAssertEqual(BarPet.chaton.nextFrame(after: 26), 1)
        XCTAssertEqual(BarPet.chaton.nextFrame(after: 25), 26)
        XCTAssertEqual(BarPet.chaton.nextFrame(after: 14), 15)
    }

    func testRestFrameIsValidCycleState() {
        let rest = BarPet.chaton.restFrame
        XCTAssertGreaterThan(rest, 0)
        XCTAssertLessThan(rest, Chaton.frames.count - 1)
        XCTAssertFalse(Chaton.frames[rest].isEmpty)
    }

    func testDotRectsMirrorTheFrameGeometry() {
        let size = CGSize(width: 230, height: 110)
        for frame in [0, 1, BarPet.chaton.restFrame, Chaton.frames.count - 1] {
            let dots = Chaton.dotRects(frame: frame, size: size)
            XCTAssertEqual(dots.count, Chaton.frames[frame].count)
            for dot in dots {
                XCTAssertTrue(CGRect(origin: .zero, size: size).contains(dot.rect),
                              "frame \(frame) dot out of bounds: \(dot.rect)")
                XCTAssertTrue((0..<Chaton.gridH).contains(dot.row))
                // Dots are 85% of a cell, never larger.
                let cell = min(size.width / Chaton.barWindow.width,
                               size.height / Chaton.barWindow.height)
                XCTAssertLessThanOrEqual(dot.rect.width, cell * 0.85 + 0.001)
            }
        }
        // Out-of-range frames clamp instead of crashing.
        XCTAssertEqual(Chaton.dotRects(frame: -3, size: size).count, Chaton.frames[0].count)
        XCTAssertEqual(Chaton.dotRects(frame: 99, size: size).count,
                       Chaton.frames[Chaton.frames.count - 1].count)
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

    func testWidgetDotSlotsKeepAllPosesInTheSameLayout() {
        let size = CGSize(width: 230, height: 110)
        let slots = Chaton.dotSlots(size: size)
        let byID = Dictionary(uniqueKeysWithValues: slots.map { ($0.id, $0.rect) })
        let allIDs = Set(Chaton.frames.flatMap { $0.map(Chaton.key) })
        XCTAssertEqual(Set(byID.keys), allIDs)
        XCTAssertEqual(slots.count, allIDs.count)
        for (index, frame) in Chaton.frames.enumerated() {
            for (cell, dot) in zip(frame, Chaton.dotRects(frame: index, size: size)) {
                XCTAssertEqual(byID[Chaton.key(cell)], dot.rect,
                               "A dot must not move when its visibility changes.")
                XCTAssertTrue(CGRect(origin: .zero, size: size).contains(dot.rect))
            }
        }
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
