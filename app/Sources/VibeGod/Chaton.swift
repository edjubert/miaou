import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

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

    /// All 27 states of the animation, state 0 being the reference pose.
    /// The cycle is periodic on states 1...26: after state 26, the first
    /// transition leads back to state 1. State 0 is only the departure
    /// pose and never comes back. The original rests on state 26;
    /// VibeGod freezes on ChatonAnimator.restFrame.
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

    /// One Int per (col, row) cell, the packing used by `frames`.
    static func key(_ c: (col: Int, row: Int)) -> Int { c.col * 32 + c.row }

    /// Silhouette of a pose: its own cells plus the empty cells they
    /// enclose, i.e. every cell a flood fill from the grid border cannot
    /// reach. The menu bar fills this silhouette black so the cat body
    /// reads solid behind the dots; the banner keeps the bare dot grid.
    static func silhouette(_ glyph: [(col: Int, row: Int)]) -> [(col: Int, row: Int)] {
        let occupied = Set(glyph.map(key))
        var reached = Set<Int>()
        var queue: [Int] = []
        func visitIfEmpty(_ col: Int, _ row: Int) {
            guard col >= 0, col < gridW, row >= 0, row < gridH else { return }
            let k = key((col, row))
            guard !occupied.contains(k), !reached.contains(k) else { return }
            reached.insert(k)
            queue.append(k)
        }
        for col in 0..<gridW {
            visitIfEmpty(col, 0)
            visitIfEmpty(col, gridH - 1)
        }
        for row in 0..<gridH {
            visitIfEmpty(0, row)
            visitIfEmpty(gridW - 1, row)
        }
        while let k = queue.popLast() {
            let col = k / 32
            let row = k % 32
            visitIfEmpty(col + 1, row)
            visitIfEmpty(col - 1, row)
            visitIfEmpty(col, row + 1)
            visitIfEmpty(col, row - 1)
        }
        var result = glyph
        for col in 0..<gridW {
            for row in 0..<gridH {
                let k = key((col, row))
                if !occupied.contains(k), !reached.contains(k) {
                    result.append((col, row))
                }
            }
        }
        return result
    }

    /// Per-frame silhouettes, in `frames` order.
    static let silhouettes: [[(col: Int, row: Int)]] = frames.map(silhouette)

    /// Reference bounding box of the pose, used to center every frame:
    /// computing it per frame would make the cat jump around.
    private static let minCol = cells.map(\.col).min()!
    private static let maxCol = cells.map(\.col).max()!
    private static let minRow = cells.map(\.row).min()!
    private static let maxRow = cells.map(\.row).max()!

    /// The glyph lives in a square grid of 25x25 cells: the pose spans
    /// cols 3-21, plus three cells of margin on the left for the tail
    /// sweep of the animation.
    private static let square: CGFloat = 25

    static func draw(in context: CGContext, size: CGFloat, palette: [NSColor]) {
        draw(cells: cells, in: context,
             window: CGRect(x: 0, y: 0, width: square, height: square),
             cell: size / square, palette: palette)
    }

    static func draw(frame: Int, in context: CGContext, size: CGFloat, palette: [NSColor]) {
        let index = min(max(frame, 0), frames.count - 1)
        draw(cells: frames[index], in: context,
             window: CGRect(x: 0, y: 0, width: square, height: square),
             cell: size / square, palette: palette)
    }

    /// Menu bar window: the cat band of the square, 25 x 14 cells. The
    /// chaton is wide, so a square image leaves it small: this window
    /// crops the vertical margins and lets it fill the bar height.
    static let barWindow = CGRect(x: 0, y: 5.5, width: 25, height: 14)

    static func drawBar(frame: Int, in context: CGContext, pixels: CGSize, palette: [NSColor]) {
        let index = min(max(frame, 0), frames.count - 1)
        let cell = CGFloat(pixels.height) / barWindow.height
        // The bar variant alone paints a backdrop behind the cat: the
        // silhouette filled dark, then blurred so it fades out a little
        // past the contour. The banner keeps the bare dot grid.
        blurBehind(silhouettes[index], in: context, pixels: pixels, cell: cell)
        draw(cells: frames[index], in: context,
             window: barWindow,
             cell: cell,
             palette: palette)
    }

    /// Shared renderer for the backdrop blur; expensive to create.
    private static let ciContext = CIContext()

    /// Halo of the bar icon: the silhouette blurred into a soft dark
    /// ring that surrounds the cat, punched out inside the contour so
    /// the cat itself stays on the bare bar background. The banner
    /// draws no halo at all.
    private static func blurBehind(_ glyph: [(col: Int, row: Int)],
                                   in context: CGContext,
                                   pixels: CGSize,
                                   cell: CGFloat) {
        let canvas = CGRect(origin: .zero, size: pixels)
        // The halo carrier: the silhouette blurred into a soft blob.
        fill(silhouette: glyph, in: context, window: barWindow, cell: cell,
             color: NSColor.black.withAlphaComponent(0.65))
        guard let dark = context.makeImage() else { return }
        context.clear(canvas)
        // The punch mask: the same silhouette in white. CIBlendWithMask
        // keys on the mask's luminance, and the fill above is black.
        fill(silhouette: glyph, in: context, window: barWindow, cell: cell,
             color: NSColor.white)
        guard let white = context.makeImage() else { return }
        context.clear(canvas)
        guard let halo = gaussianBlur(CIImage(cgImage: dark), radius: cell * 0.8),
              let mask = gaussianBlur(CIImage(cgImage: white), radius: cell * 0.35)
        else { return }
        // Halo outside the (feathered) mask, transparent inside it.
        let blend = CIFilter.blendWithMask()
        blend.inputImage = CIImage.empty()
        blend.backgroundImage = halo
        blend.maskImage = mask
        guard let output = blend.outputImage,
              let ring = ciContext.createCGImage(output, from: canvas) else { return }
        context.draw(ring, in: canvas)
    }

    private static func gaussianBlur(_ image: CIImage, radius: CGFloat) -> CIImage? {
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = image
        filter.radius = Float(radius)
        return filter.outputImage
    }

    /// Full-cell rectangles of `glyph` painted `color`, mirroring the
    /// geometry of `draw`. Rects overlap a hair so antialiasing leaves
    /// no seams between adjacent cells.
    private static func fill(silhouette glyph: [(col: Int, row: Int)],
                             in context: CGContext,
                             window: CGRect,
                             cell: CGFloat,
                             color: NSColor) {
        let marginX = (square - CGFloat(maxCol - minCol + 1)) / 2
        let marginY = (square - CGFloat(maxRow - minRow + 1)) / 2
        let height = window.height * cell
        let overlap = cell * 0.1
        context.setFillColor(color.cgColor)
        for c in glyph {
            let x = (marginX + CGFloat(c.col - minCol) - window.minX) * cell
            let top = (marginY + CGFloat(c.row - minRow) - window.minY) * cell
            let rect = CGRect(
                x: x - overlap,
                y: height - top - cell - overlap,
                width: cell + 2 * overlap,
                height: cell + 2 * overlap
            )
            context.fill(rect)
        }
    }

    private static func draw(cells glyph: [(col: Int, row: Int)],
                             in context: CGContext,
                             window: CGRect,
                             cell: CGFloat,
                             palette: [NSColor]) {
        let dot = cell * 0.7
        let inset = (cell - dot) / 2
        let marginX = (square - CGFloat(maxCol - minCol + 1)) / 2
        let marginY = (square - CGFloat(maxRow - minRow + 1)) / 2
        let height = window.height * cell
        for c in glyph {
            let x = (marginX + CGFloat(c.col - minCol) - window.minX) * cell + inset
            let top = (marginY + CGFloat(c.row - minRow) - window.minY) * cell + inset
            let rect = CGRect(x: x, y: height - top - dot, width: dot, height: dot)
            context.setFillColor(palette[min(4, c.row * 5 / 12)].cgColor)
            context.fill(rect)
        }
    }
}
