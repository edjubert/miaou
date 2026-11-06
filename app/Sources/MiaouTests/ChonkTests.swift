import XCTest
@testable import Miaou

final class ChonkTests: XCTestCase {
    private func key(_ c: (col: Int, row: Int)) -> Int {
        c.col * 32 + c.row
    }

    private func set(_ cells: [(col: Int, row: Int)]) -> Set<Int> {
        Set(cells.map(key))
    }

    func testAnimationFrameCount() {
        // Reference pose + 16 transitions.
        XCTAssertEqual(Chonk.frames.count, Chonk.transitions.count + 1)
        XCTAssertEqual(Chonk.frames.count, 17)
    }

    func testFirstFrameIsReferencePose() {
        XCTAssertEqual(set(Chonk.frames[0]), set(Chonk.cells))
    }

    func testFramesStayInGrid() {
        for (i, frame) in Chonk.frames.enumerated() {
            for c in frame {
                XCTAssertTrue((0..<Chonk.gridW).contains(c.col), "frame \(i) col \(c.col)")
                XCTAssertTrue((0..<Chonk.gridH).contains(c.row), "frame \(i) row \(c.row)")
            }
            // A transition never adds a cell twice to the same frame.
            XCTAssertEqual(frame.count, set(frame).count, "frame \(i) has duplicates")
        }
    }

    func testAnimationClosesOnReferencePose() {
        // The chonk cycle is exact: after the last state, applying the
        // first transition again leads back to the second state, and the
        // last state is the reference pose itself.
        XCTAssertEqual(set(Chonk.frames[Chonk.frames.count - 1]), set(Chonk.frames[0]))
        let rest = set(Chonk.frames[Chonk.frames.count - 1])
        let loop = rest
            .subtracting(set(Chonk.transitions[0].remove))
            .union(set(Chonk.transitions[0].add))
        XCTAssertEqual(loop, set(Chonk.frames[1]))
    }

    func testCycleWrapsAfterLastState() {
        // Periodic loop on states 1...16: state 0 is never revisited.
        XCTAssertEqual(BarPet.chonk.nextFrame(after: 16), 1)
        XCTAssertEqual(BarPet.chonk.nextFrame(after: 15), 16)
        XCTAssertEqual(BarPet.chonk.nextFrame(after: 7), 8)
    }

    func testRestFrameIsValidCycleState() {
        let rest = BarPet.chonk.restFrame
        XCTAssertGreaterThan(rest, 0)
        XCTAssertLessThanOrEqual(rest, Chonk.frames.count - 1)
        XCTAssertFalse(Chonk.frames[rest].isEmpty)
    }

    func testSilhouettesCoverTheirFrames() {
        for (i, pose) in Chonk.frames.enumerated() {
            let dots = Set(pose.map(key))
            let silKeys = Set(Chonk.silhouettes[i].map(key))
            XCTAssertTrue(silKeys.isSuperset(of: dots), "frame \(i)")
        }
        XCTAssertEqual(Chonk.silhouettes.count, Chonk.frames.count)
    }

    func testIsChonkModelDetection() {
        XCTAssertTrue(ModelRefReport(name: "mistral-large-4", alias: "Le Chonk").isChonk)
        XCTAssertTrue(ModelRefReport(name: "mistral-large-4-0-3", alias: nil).isChonk)
        XCTAssertTrue(ModelRefReport(name: "anything", alias: "Le Chonk").isChonk)
        XCTAssertFalse(ModelRefReport(name: "mistral-small-latest", alias: "Small 4").isChonk)
        XCTAssertFalse(ModelRefReport(name: "mistral-large-4-flash", alias: nil).isChonk)
        XCTAssertFalse(ModelRefReport(name: "zai-glm-5-3", alias: "glm-5-3").isChonk)
    }
}
