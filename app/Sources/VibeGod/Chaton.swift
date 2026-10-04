import AppKit

/// Le petit chat: the cat of the Mistral Vibe CLI banner (see
/// vibe/cli/textual_ui/widgets/banner/petit_chat.py), re-rendered as
/// small square dots instead of braille characters. The dot grid below
/// is the reference pose from STARTING_DOTS: a slim sitting cat facing
/// right, curled tail on the left, eyes on row 5, resting on a ground
/// line.
///
/// Geometry: 22x12 cells fitted in the shared 24x24 viewBox, aspect
/// preserved (cell = 24/22). The pose leaves empty cells on the left
/// (cols 0-2) and on top/bottom (rows 0 and 11), so the dot bounding
/// box is what gets centered, not the raw grid. Each cell renders as a
/// centered square dot of 0.7 cell, leaving an even gap. Rows map to
/// palette bands: rows 0-2 -> 0, 3-4 -> 1, 5-7 -> 2, 8-9 -> 3,
/// 10-11 -> 4.
enum Chaton {
    static let gridW = 22
    static let gridH = 12

    /// Filled cells as (col, row), transcribed from the banner pose.
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

    static func draw(in context: CGContext, size: CGFloat, palette: [NSColor]) {
        let cell = size / CGFloat(gridW)
        let dot = cell * 0.7
        let inset = (cell - dot) / 2
        // Center the dot bounding box, not the raw grid.
        let minCol = cells.map(\.col).min()!
        let maxCol = cells.map(\.col).max()! + 1
        let minRow = cells.map(\.row).min()!
        let maxRow = cells.map(\.row).max()! + 1
        let offsetX = (size - CGFloat(maxCol - minCol) * cell) / 2
        let offsetY = (size - CGFloat(maxRow - minRow) * cell) / 2
        for c in cells {
            let x = offsetX + CGFloat(c.col - minCol) * cell + inset
            // Row 0 is the top: convert to the context's bottom-left origin.
            let y = size - offsetY - CGFloat(c.row - minRow) * cell - inset - dot
            let rect = CGRect(x: x, y: y, width: dot, height: dot)
            context.setFillColor(palette[min(4, c.row * 5 / 12)].cgColor)
            context.fill(rect)
        }
    }
}
