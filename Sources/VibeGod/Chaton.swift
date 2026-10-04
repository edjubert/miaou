import AppKit

/// Le petit chat: the cat of the Mistral Vibe CLI banner (see
/// vibe/cli/textual_ui/widgets/banner/petit_chat.py), re-rendered as
/// small square dots instead of braille characters. The dot grids below
/// are transcribed from the source module: the reference pose from
/// STARTING_DOTS and the 26 transitions of its idle animation (tail
/// sweep, head turns, blinks), 0.16 s per frame like the original.
///
/// Geometry: 22x12 cells fitted in the shared 24x24 viewBox. The pose
/// leaves empty cells on the left (cols 0-2) and on top/bottom (rows 0
/// and 11), but the tail sweep of the animation reaches col 0, so the
/// cell pitch is 24/25: the reference pose (cols 3-21) is centered with
/// exactly three cells of margin for the sweep. Each cell renders as a
/// centered square dot of 0.7 cell, leaving an even gap. Rows map to
/// palette bands: rows 0-2 -> 0, 3-4 -> 1, 5-7 -> 2, 8-9 -> 3,
/// 10-11 -> 4.
enum Chaton {
    static let gridW = 22
    static let gridH = 12

    /// Reference pose cells as (col, row), transcribed from STARTING_DOTS.
    static let cells: [(col: Int, row: Int)] = [
        // Row 1
        (6, 1), (7, 1), (15, 1), (19, 1),
        // Row 2
        (5, 2), (8, 2), (14, 2), (16, 2), (18, 2), (20, 2),
        // Row 3
        (4, 3), (6, 3), (7, 3), (14, 3), (17, 3), (20, 3),
        // Row 4
        (3, 4), (5, 4), (10, 4), (11, 4), (12, 4), (14, 4), (20, 4),
        // Row 5
        (3, 5), (5, 5), (9, 5), (13, 5), (14, 5), (16, 5), (18, 5), (20, 5),
        // Row 6
        (3, 6), (5, 6), (8, 6), (13, 6), (17, 6), (21, 6),
        // Row 7
        (3, 7), (6, 7), (7, 7), (8, 7), (11, 7), (14, 7), (15, 7), (16, 7), (18, 7), (19, 7), (20, 7),
        // Row 8
        (4, 8), (5, 8), (8, 8), (12, 8), (17, 8), (19, 8),
        // Row 9
        (6, 9), (7, 9), (8, 9), (13, 9), (18, 9), (20, 9),
        // Row 10
        (9, 10), (10, 10), (11, 10), (12, 10), (13, 10), (14, 10), (15, 10), (16, 10), (17, 10), (18, 10), (19, 10), (20, 10),
    ]

    /// Animation transitions, transcribed from TRANSITIONS. Each entry
    /// removes and adds cells. Applying them in order, then looping
    /// back to the first, is an exact cycle: the animation is periodic.
    static let transitions: [(remove: [(col: Int, row: Int)], add: [(col: Int, row: Int)])] = [
        // 1
        (remove: [(16, 5), (18, 5)], add: []),
        // 2
        (remove: [], add: [(16, 5), (18, 5)]),
        // 3
        (remove: [], add: []),
        // 4
        (remove: [(6, 1), (7, 1), (8, 2), (4, 3), (6, 3), (7, 3), (4, 8), (5, 8)], add: [(4, 1), (3, 2), (3, 3), (5, 3), (5, 7), (3, 8), (4, 9), (5, 9)]),
        // 5
        (remove: [(16, 5), (18, 5), (17, 6)], add: [(17, 5), (19, 5), (18, 6)]),
        // 6
        (remove: [], add: []),
        // 7
        (remove: [(4, 1), (5, 2), (3, 3), (5, 3), (5, 7), (3, 8), (4, 9), (5, 9)], add: [(1, 1), (2, 1), (0, 2), (1, 3), (2, 3), (4, 3), (4, 8), (5, 8)]),
        // 8
        (remove: [], add: []),
        // 9
        (remove: [(1, 1), (2, 1), (0, 2), (1, 3), (2, 3), (4, 3), (4, 8), (5, 8)], add: [(4, 1), (5, 2), (3, 3), (5, 3), (5, 7), (3, 8), (4, 9), (5, 9)]),
        // 10
        (remove: [], add: []),
        // 11
        (remove: [(15, 1), (19, 1), (14, 2), (16, 2), (18, 2), (20, 2), (17, 3), (17, 5), (19, 5), (13, 6), (18, 6), (21, 6), (14, 7), (15, 7), (16, 7), (19, 7), (20, 7)], add: [(15, 2), (19, 2), (16, 3), (18, 3), (17, 4), (14, 6), (17, 6), (19, 6), (20, 6), (13, 7), (18, 7), (21, 7), (14, 8), (15, 8), (16, 8), (18, 8), (20, 8)]),
        // 12
        (remove: [], add: []),
        // 13
        (remove: [(4, 1), (3, 2), (3, 3), (5, 3), (5, 7), (3, 8), (4, 9), (5, 9)], add: [(6, 1), (7, 1), (8, 2), (4, 3), (6, 3), (7, 3), (4, 8), (5, 8)]),
        // 14
        (remove: [(17, 6), (19, 6)], add: []),
        // 15
        (remove: [], add: [(17, 6), (19, 6)]),
        // 16
        (remove: [], add: []),
        // 17
        (remove: [(6, 1), (7, 1), (8, 2), (4, 3), (6, 3), (7, 3), (4, 8), (5, 8)], add: [(4, 1), (3, 2), (3, 3), (5, 3), (5, 7), (3, 8), (4, 9), (5, 9)]),
        // 18
        (remove: [], add: []),
        // 19
        (remove: [(4, 1), (5, 2), (3, 3), (5, 3), (5, 7), (3, 8), (4, 9), (5, 9)], add: [(1, 1), (2, 1), (0, 2), (1, 3), (2, 3), (4, 3), (4, 8), (5, 8)]),
        // 20
        (remove: [], add: []),
        // 21
        (remove: [(15, 2), (19, 2), (16, 3), (18, 3), (17, 4), (14, 6), (17, 6), (19, 6), (20, 6), (13, 7), (18, 7), (21, 7), (14, 8), (15, 8), (16, 8), (18, 8), (20, 8)], add: [(15, 1), (19, 1), (14, 2), (16, 2), (18, 2), (20, 2), (17, 3), (17, 5), (19, 5), (13, 6), (18, 6), (21, 6), (14, 7), (15, 7), (16, 7), (18, 7), (19, 7), (20, 7)]),
        // 22
        (remove: [], add: []),
        // 23
        (remove: [(1, 1), (2, 1), (0, 2), (1, 3), (2, 3), (4, 3), (4, 8), (5, 8)], add: [(4, 1), (5, 2), (3, 3), (5, 3), (5, 7), (3, 8), (4, 9), (5, 9)]),
        // 24
        (remove: [(17, 5), (19, 5), (18, 6)], add: [(16, 5), (18, 5), (17, 6)]),
        // 25
        (remove: [], add: []),
        // 26
        (remove: [(4, 1), (3, 2), (3, 3), (5, 3), (5, 7), (3, 8), (4, 9), (5, 9)], add: [(6, 1), (7, 1), (8, 2), (4, 3), (6, 3), (7, 3), (4, 8), (5, 8)]),
    ]

    /// All 27 states of the animation, state 0 being the reference pose
    /// and state 26 the rest pose the original pauses on.
    static let frames: [[(col: Int, row: Int)]] = {
        func key(_ c: (col: Int, row: Int)) -> Int { c.col * 32 + c.row }
        var current = Set(cells.map(key))
        var result = [cells]
        for t in transitions {
            current.subtract(t.remove.map(key))
            current.formUnion(t.add.map(key))
            result.append(current.sorted().map { ($0 / 32, $0 % 32) })
        }
        return result
    }()

    /// Reference bounding box of the pose, used to center every frame:
    /// computing it per frame would make the cat jump around.
    private static let minCol = cells.map(\.col).min()!
    private static let maxCol = cells.map(\.col).max()!
    private static let minRow = cells.map(\.row).min()!
    private static let maxRow = cells.map(\.row).max()!

    static func draw(in context: CGContext, size: CGFloat, palette: [NSColor]) {
        draw(cells: cells, in: context, size: size, palette: palette)
    }

    static func draw(frame: Int, in context: CGContext, size: CGFloat, palette: [NSColor]) {
        let index = min(max(frame, 0), frames.count - 1)
        draw(cells: frames[index], in: context, size: size, palette: palette)
    }

    private static func draw(cells glyph: [(col: Int, row: Int)], in context: CGContext, size: CGFloat, palette: [NSColor]) {
        // Pitch 24/25 instead of 24/22: the tail sweep of the animation
        // reaches col 0, which lands exactly on the viewBox edge.
        let cell = size / 25
        let dot = cell * 0.7
        let inset = (cell - dot) / 2
        let offsetX = (size - CGFloat(maxCol - minCol + 1) * cell) / 2
        let offsetY = (size - CGFloat(maxRow - minRow + 1) * cell) / 2
        for c in glyph {
            let x = offsetX + CGFloat(c.col - minCol) * cell + inset
            // Row 0 is the top: convert to the context's bottom-left origin.
            let y = size - offsetY - CGFloat(c.row - minRow) * cell - inset - dot
            let rect = CGRect(x: x, y: y, width: dot, height: dot)
            context.setFillColor(palette[min(4, c.row * 5 / 12)].cgColor)
            context.fill(rect)
        }
    }
}
