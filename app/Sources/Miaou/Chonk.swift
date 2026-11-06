import AppKit

/// Le chonk: the big cat of the Mistral Vibe CLI banner shown when the
/// active model is "Le Chonk" (mistral-large-4). The reference pose and
/// its 16 animation transitions are transcribed from chonk.mov. The
/// cycle closes exactly on the reference pose, also the rest pose.
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

    /// Reference pose sampled at the centers of the recorded braille dots.
    static let cells: [(col: Int, row: Int)] = [
        // Row 0
        (11, 0), (12, 0), (13, 0), (14, 0), (15, 0), (17, 0), (21, 0),
        // Row 1
        (10, 1), (16, 1), (18, 1), (20, 1), (22, 1),
        // Row 2
        (9, 2), (16, 2), (19, 2), (22, 2),
        // Row 3
        (8, 3), (16, 3), (22, 3),
        // Row 4
        (6, 4), (7, 4), (8, 4), (15, 4), (18, 4), (20, 4), (23, 4),
        // Row 5
        (5, 5), (8, 5), (15, 5), (19, 5), (23, 5),
        // Row 6
        (4, 6), (6, 6), (7, 6), (8, 6), (16, 6), (17, 6), (18, 6), (20, 6), (21, 6), (22, 6),
        // Row 7
        (2, 7), (3, 7), (4, 7), (6, 7), (7, 7), (14, 7), (15, 7), (18, 7), (21, 7),
        // Row 8
        (1, 8), (5, 8), (7, 8), (16, 8), (19, 8), (22, 8),
        // Row 9
        (2, 9), (3, 9), (4, 9), (7, 9), (8, 9), (9, 9), (10, 9), (11, 9), (12, 9), (13, 9), (14, 9), (15, 9), (16, 9), (17, 9), (18, 9), (19, 9), (20, 9), (21, 9), (22, 9),
    ]

    /// Successive changes of pose, each removing and adding dots.
    static let transitions: [(remove: [(col: Int, row: Int)], add: [(col: Int, row: Int)])] = [
        // 1
        (remove: [(18, 4), (20, 4), (19, 5)], add: []),
        // 2
        (remove: [], add: [(18, 4), (20, 4), (19, 5)]),
        // 3
        (remove: [(5, 5), (2, 7), (3, 7), (4, 7), (6, 7), (1, 8), (5, 8), (2, 9), (3, 9), (4, 9)], add: [(1, 4), (2, 4), (3, 4), (4, 4), (5, 4), (0, 5), (1, 6), (2, 6), (3, 6), (5, 6)]),
        // 4
        (remove: [(18, 4), (20, 4), (19, 5)], add: [(19, 4), (21, 4), (20, 5)]),
        // 5
        (remove: [(1, 4), (2, 4), (3, 4), (5, 4), (0, 5), (1, 6), (2, 6), (3, 6), (4, 6), (5, 6)], add: [(2, 1), (3, 1), (4, 1), (1, 2), (5, 2), (2, 3), (3, 3), (4, 3), (6, 3), (5, 5)]),
        // 6
        (remove: [(2, 1), (3, 1), (4, 1), (1, 2), (5, 2), (2, 3), (3, 3), (4, 3), (6, 3), (5, 5)], add: [(1, 4), (2, 4), (3, 4), (5, 4), (0, 5), (1, 6), (2, 6), (3, 6), (4, 6), (5, 6)]),
        // 7
        (remove: [(17, 0), (21, 0), (18, 1), (20, 1), (22, 1), (19, 2), (15, 4), (19, 4), (21, 4), (23, 4), (20, 5), (16, 6), (17, 6), (18, 6), (21, 6), (22, 6)], add: [(17, 1), (21, 1), (18, 2), (20, 2), (19, 3), (16, 4), (22, 4), (19, 5), (21, 5), (15, 6), (23, 6), (16, 7), (17, 7), (20, 7), (22, 7)]),
        // 8
        (remove: [(1, 4), (2, 4), (3, 4), (4, 4), (5, 4), (0, 5), (1, 6), (2, 6), (3, 6), (5, 6)], add: [(5, 5), (2, 7), (3, 7), (4, 7), (6, 7), (1, 8), (5, 8), (2, 9), (3, 9), (4, 9)]),
        // 9
        (remove: [(19, 5), (21, 5), (20, 6)], add: []),
        // 10
        (remove: [], add: [(19, 5), (21, 5), (20, 6)]),
        // 11
        (remove: [(5, 5), (2, 7), (3, 7), (4, 7), (6, 7), (1, 8), (5, 8), (2, 9), (3, 9), (4, 9)], add: [(1, 4), (2, 4), (3, 4), (4, 4), (5, 4), (0, 5), (1, 6), (2, 6), (3, 6), (5, 6)]),
        // 12
        (remove: [(1, 4), (2, 4), (3, 4), (5, 4), (0, 5), (1, 6), (2, 6), (3, 6), (4, 6), (5, 6)], add: [(2, 1), (3, 1), (4, 1), (1, 2), (5, 2), (2, 3), (3, 3), (4, 3), (6, 3), (5, 5)]),
        // 13
        (remove: [(17, 1), (21, 1), (18, 2), (20, 2), (19, 3), (16, 4), (22, 4), (19, 5), (21, 5), (15, 6), (23, 6), (16, 7), (17, 7), (20, 7), (22, 7)], add: [(17, 0), (21, 0), (18, 1), (20, 1), (22, 1), (19, 2), (15, 4), (19, 4), (21, 4), (23, 4), (20, 5), (16, 6), (17, 6), (18, 6), (21, 6), (22, 6)]),
        // 14
        (remove: [(2, 1), (3, 1), (4, 1), (1, 2), (5, 2), (2, 3), (3, 3), (4, 3), (6, 3), (5, 5)], add: [(1, 4), (2, 4), (3, 4), (5, 4), (0, 5), (1, 6), (2, 6), (3, 6), (4, 6), (5, 6)]),
        // 15
        (remove: [(19, 4), (21, 4), (20, 5)], add: [(18, 4), (20, 4), (19, 5)]),
        // 16
        (remove: [(1, 4), (2, 4), (3, 4), (4, 4), (5, 4), (0, 5), (1, 6), (2, 6), (3, 6), (5, 6)], add: [(5, 5), (2, 7), (3, 7), (4, 7), (6, 7), (1, 8), (5, 8), (2, 9), (3, 9), (4, 9)]),
    ]

    /// One cell of room to the left for the tail sweep.
    static let square: CGFloat = 26

    /// Half a cell above and below the ten rows of dots.
    static let barWindow = CGRect(x: 0, y: 7.5, width: 25, height: 11)
}
