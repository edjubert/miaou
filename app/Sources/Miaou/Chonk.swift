import AppKit

/// Le chonk: the big cat of the Mistral Vibe CLI banner shown when the
/// active model is "Le Chonk" (mistral-large-4). The outlines come from
/// chonk.mov; in this idle story the cat wakes, raises its head, swishes
/// its tail while looking at the user and to the right twice, then
/// settles back to sleep.
///
/// Geometry: 24 columns and 10 rows of dots. In the recorded terminal,
/// columns are 4 px apart, while rows alternate between 4 and 5 px.
/// Sampling each actual row once avoids doubled eyes, tail and baseline.
/// The dots are re-rendered on the same square lattice as the petit chat.
/// The reference pose spans cols 1-23; the tail reaches col 0. A fixed
/// 25x11 crop keeps every pose centered with half a cell above and below.
enum Chonk: PetGlyph {
    static let gridW = 24
    static let gridH = 10

    private typealias Cell = (col: Int, row: Int)

    /// Raised head without the eyes and nose, sampled from the recording.
    private static let raisedOutline: [Cell] = [
        // Row 0
        (11, 0), (12, 0), (13, 0), (14, 0), (15, 0), (17, 0), (21, 0),
        // Row 1
        (10, 1), (16, 1), (18, 1), (20, 1), (22, 1),
        // Row 2
        (9, 2), (16, 2), (19, 2), (22, 2),
        // Row 3
        (8, 3), (16, 3), (22, 3),
        // Row 4
        (6, 4), (7, 4), (8, 4), (15, 4), (23, 4),
        // Row 5
        (5, 5), (8, 5), (15, 5), (23, 5),
        // Row 6
        (4, 6), (6, 6), (7, 6), (8, 6), (16, 6), (17, 6), (18, 6), (20, 6), (21, 6), (22, 6),
        // Row 7
        (2, 7), (3, 7), (4, 7), (6, 7), (7, 7), (14, 7), (15, 7), (18, 7), (21, 7),
        // Row 8
        (1, 8), (5, 8), (7, 8), (16, 8), (19, 8), (22, 8),
        // Row 9
        (2, 9), (3, 9), (4, 9), (7, 9), (8, 9), (9, 9), (10, 9), (11, 9), (12, 9), (13, 9), (14, 9), (15, 9), (16, 9), (17, 9), (18, 9), (19, 9), (20, 9), (21, 9), (22, 9),
    ]

    /// Lower only the head by one row; leave the back, paws and tail still.
    private static let loweredOutline: [Cell] = {
        let removed: [Cell] = [
            (17, 0), (21, 0), (18, 1), (20, 1), (22, 1), (19, 2),
            (15, 4), (23, 4), (16, 6), (17, 6), (18, 6), (20, 6), (21, 6), (22, 6),
        ]
        let added: [Cell] = [
            (17, 1), (21, 1), (18, 2), (20, 2), (19, 3), (16, 4), (22, 4),
            (15, 6), (23, 6), (16, 7), (17, 7), (20, 7), (22, 7),
        ]
        let removedKeys = Set(removed.map(key))
        return raisedOutline.filter { !removedKeys.contains(key($0)) } + added
    }()

    /// Like the petit chat, closed eyes disappear while the nose remains.
    static let cells: [(col: Int, row: Int)] = loweredOutline + [(19, 6)]

    /// Each tick lasts 0.16 s. Repeated poses give the cat time to look.
    static let transitions: [(remove: [(col: Int, row: Int)], add: [(col: Int, row: Int)])] = {
        let waking = loweredOutline + [(18, 5), (20, 5), (19, 6)]
        let watching = raisedOutline + [(18, 4), (20, 4), (19, 5)]
        let watchingBlink = raisedOutline + [(19, 5)]
        let lookingRight = raisedOutline + [(19, 4), (21, 4), (20, 5)]
        let rightBlink = raisedOutline + [(20, 5)]
        let lowering = loweredOutline + [(19, 5), (21, 5), (20, 6)]
        // The three tail poses from the original Chonk, including the
        // attachment at (4, 6) that moves when the tail rises.
        let curledTail: [Cell] = [
            (5, 5), (4, 6), (2, 7), (3, 7), (4, 7), (6, 7),
            (1, 8), (5, 8), (2, 9), (3, 9), (4, 9),
        ]
        let stretchedTail: [Cell] = [
            (1, 4), (2, 4), (3, 4), (4, 4), (5, 4), (0, 5),
            (1, 6), (2, 6), (3, 6), (4, 6), (5, 6),
        ]
        let raisedTail: [Cell] = [
            (2, 1), (3, 1), (4, 1), (1, 2), (5, 2),
            (2, 3), (3, 3), (4, 3), (6, 3), (4, 4), (5, 5),
        ]
        let curledTailKeys = Set(curledTail.map(key))
        let tailSwing = [stretchedTail, raisedTail, stretchedTail, curledTail]
        let story: [(pose: [Cell], ticks: Int, wagsTail: Bool)] = [
            (cells, 12, false),        // Sleep.
            (waking, 3, false),        // Open the eyes before lifting the head.
            (watching, 2, true),       // Look at the user.
            (watchingBlink, 1, true),  // Blink once, keeping the nose visible.
            (watching, 3, true),
            (lookingRight, 2, true),   // Look to the right.
            (rightBlink, 1, true),     // Blink once during this first rightward gaze.
            (lookingRight, 2, true),
            (watching, 5, true),       // Look at the user again.
            (lookingRight, 6, true),   // One more look to the right.
            (lowering, 2, false),      // Settle the head and tail back down.
            (cells, 2, false),         // Close the eyes; the loop ends asleep.
        ]
        var previous = Set(cells.map(key))
        var tailTick = 0
        return story.flatMap { beat in
            (0..<beat.ticks).map { _ in
                var next = Set(beat.pose.map(key))
                if beat.wagsTail {
                    // Keep the swing running across changes of gaze.
                    // Each tail pose lasts three ticks, or 0.48 s.
                    next.subtract(curledTailKeys)
                    next.formUnion(tailSwing[(tailTick / 3) % tailSwing.count].map(key))
                    tailTick += 1
                }
                let change = (
                    remove: previous.subtracting(next).sorted().map { (col: $0 / 32, row: $0 % 32) },
                    add: next.subtracting(previous).sorted().map { (col: $0 / 32, row: $0 % 32) }
                )
                previous = next
                return change
            }
        }
    }()

    /// Keep the original framing for the broad body.
    static let square: CGFloat = 26

    /// Half a cell above and below the ten rows of dots.
    static let barWindow = CGRect(x: 0, y: 7.5, width: 25, height: 11)
}
