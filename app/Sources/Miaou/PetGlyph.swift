import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// A dotted pet glyph of the Vibe CLI banner (the petit chat, the chonk
/// shown for the "Le Chonk" model), re-rendered as small square dots
/// instead of braille characters.
///
/// A conforming type provides the grid size, the reference pose and the
/// animation transitions; this extension derives the frames and the
/// silhouettes, and implements the whole dot renderer shared by every pet.
///
/// Geometry: the pose is centered in a square of `square`x`square` cells
/// fitted in the shared 24x24 viewBox, so the cell pitch is 24/square.
/// Each cell renders as a centered square dot of 0.85 cell, leaving an
/// even gap. The dot rects used by the desktop pet and the widget keep at
/// least 1 pt of gap, so small renders never merge adjacent pixels.
/// Each glyph's grid height divides the rows into five palette
/// bands, from gold at the top to red at the bottom.
protocol PetGlyph {
    static var gridW: Int { get }
    static var gridH: Int { get }

    /// Reference pose cells as (col, row).
    static var cells: [(col: Int, row: Int)] { get }

    /// Animation transitions. Each entry removes and adds cells. Applying
    /// them in order, then looping back to the first, is an exact cycle:
    /// the animation is periodic.
    static var transitions: [(remove: [(col: Int, row: Int)], add: [(col: Int, row: Int)])] { get }

    /// Side of the square cell grid the pose is centered in.
    static var square: CGFloat { get }

    /// Crop of the square used by the menu bar and banner variants.
    static var barWindow: CGRect { get }
}

/// A protocol extension cannot store properties; the shared CIContext
/// (expensive to create) lives here.
enum PetRenderCache {
    static let ciContext = CIContext()
}

extension PetGlyph {
    /// All states of the animation, state 0 being the reference pose.
    /// The cycle is periodic on states 1...N: after the last state, the
    /// first transition leads back to the second one. State 0 is only the
    /// departure pose and never comes back.
    static var frames: [[(col: Int, row: Int)]] {
        func key(_ c: (col: Int, row: Int)) -> Int { c.col * 32 + c.row }
        var current = Set(cells.map(key))
        var result = [cells]
        for t in transitions {
            current.subtract(t.remove.map(key))
            current.formUnion(t.add.map(key))
            result.append(current.sorted().map { ($0 / 32, $0 % 32) })
        }
        return result
    }

    /// One Int per (col, row) cell, the packing used by `frames`.
    static func key(_ c: (col: Int, row: Int)) -> Int { c.col * 32 + c.row }

    /// Silhouette of a pose: its own cells plus the empty cells they
    /// enclose, i.e. every cell a flood fill from the grid border cannot
    /// reach. The menu bar fills this silhouette black so the pet body
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
    static var silhouettes: [[(col: Int, row: Int)]] { frames.map(silhouette) }

    /// Reference bounding box of the pose, used to center every frame:
    /// computing it per frame would make the pet jump around.
    private static var minCol: Int { cells.map(\.col).min()! }
    private static var maxCol: Int { cells.map(\.col).max()! }
    private static var minRow: Int { cells.map(\.row).min()! }
    private static var maxRow: Int { cells.map(\.row).max()! }

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

    /// Menu bar and banner window: the band of the square around the
    /// pose. The pets are wide, so a square image leaves them small:
    /// this window crops the margins around the pose. Each pet declares
    /// its own `barWindow`. The pose fills about 9 tenths of the bar
    /// height.
    static func drawBar(frame: Int, in context: CGContext, pixels: CGSize, palette: [NSColor]) {
        let index = min(max(frame, 0), frames.count - 1)
        let cell = CGFloat(pixels.height) / barWindow.height
        // The bar variant alone paints a backdrop behind the pet: the
        // silhouette blurred into a halo. The banner draws bare dots.
        blurBehind(silhouettes[index], in: context, pixels: pixels, cell: cell)
        draw(cells: frames[index], in: context,
             window: barWindow,
             cell: cell,
             palette: palette)
    }

    /// Dot geometry in a top-left-origin SwiftUI box, using the same
    /// fixed crop as the banner so changing poses never shifts the pet.
    /// Dots keep at least 1 pt between them so small sizes stay readable.
    /// With a backing `scale`, the grid snaps to whole device pixels and
    /// the gap to an even number of device pixels (at least two), so
    /// non-antialiased drawing never merges adjacent dots.
    static func dotRects(frame: Int, size: CGSize, scale: CGFloat = 0) -> [(rect: CGRect, row: Int)] {
        let index = min(max(frame, 0), frames.count - 1)
        return dotRects(cells: frames[index], size: size, minimumGap: 1, scale: scale)
    }

    /// The glass backdrop of the desktop pet: each silhouette cell shrunk
    /// to its dot and extended into the gaps toward neighboring cells, so
    /// the backdrop fills the body and the dot gaps without sticking out
    /// past the outermost dots.
    static func glassRects(frame: Int, size: CGSize, scale: CGFloat = 0) -> [CGRect] {
        let index = min(max(frame, 0), frames.count - 1)
        let (cell, offsetX, offsetY) = grid(size: size, scale: scale)
        let inset = dotGap(cell: cell, minimumGap: 1, scale: scale) / 2
        let cells = silhouettes[index]
        let keys = Set(cells.map(key))
        return cells.map { c in
            var rect = cellRect(col: c.col, row: c.row, cell: cell,
                                offsetX: offsetX, offsetY: offsetY)
                .insetBy(dx: inset, dy: inset)
            if keys.contains(key((c.col + 1, c.row))) { rect.size.width += inset }
            if keys.contains(key((c.col - 1, c.row))) {
                rect.origin.x -= inset
                rect.size.width += inset
            }
            if keys.contains(key((c.col, c.row + 1))) { rect.size.height += inset }
            if keys.contains(key((c.col, c.row - 1))) {
                rect.origin.y -= inset
                rect.size.height += inset
            }
            return rect
        }
    }

    /// All possible dots have stable identities and positions; only
    /// their opacity changes when WidgetKit advances to another pose.
    static func dotSlots(size: CGSize) -> [(id: Int, rect: CGRect, row: Int)] {
        let animationCells = Set(frames.flatMap { $0.map(key) }).sorted().map {
            (col: $0 / 32, row: $0 % 32)
        }
        return zip(animationCells, dotRects(cells: animationCells, size: size, minimumGap: 1)).map {
            (key($0.0), $0.1.rect, $0.1.row)
        }
    }

    /// The cell grid fitted in `size`: cell pitch and centering offsets.
    /// With a backing `scale`, the grid snaps down to whole device pixels
    /// so the pet still fits the view.
    private static func grid(size: CGSize, scale: CGFloat)
        -> (cell: CGFloat, offsetX: CGFloat, offsetY: CGFloat) {
        let window = barWindow
        var cell = min(size.width / window.width, size.height / window.height)
        var offsetX = (size.width - window.width * cell) / 2
        var offsetY = (size.height - window.height * cell) / 2
        if scale > 0 {
            cell = floor(cell * scale) / scale
            offsetX = round(offsetX * scale) / scale
            offsetY = round(offsetY * scale) / scale
        }
        return (cell, offsetX, offsetY)
    }

    /// The full cell of a grid position, in top-left-origin coordinates.
    private static func cellRect(col: Int, row: Int,
                                 cell: CGFloat, offsetX: CGFloat, offsetY: CGFloat) -> CGRect {
        let window = barWindow
        let marginX = (square - CGFloat(maxCol - minCol + 1)) / 2
        let marginY = (square - CGFloat(maxRow - minRow + 1)) / 2
        let x = offsetX + (marginX + CGFloat(col - minCol) - window.minX) * cell
        let y = offsetY + (marginY + CGFloat(row - minRow) - window.minY) * cell
        return CGRect(x: x, y: y, width: cell, height: cell)
    }

    /// The margin between dots: 15% of a cell, but never below
    /// `minimumGap`. With a backing `scale`, snapped to an even number of
    /// device pixels (at least two), so drawing without antialiasing keeps
    /// a visible margin between dots.
    private static func dotGap(cell: CGFloat, minimumGap: CGFloat, scale: CGFloat) -> CGFloat {
        var gap = max(cell * 0.15, minimumGap)
        if scale > 0 {
            var gapPixels = Int(round(gap * scale))
            if gapPixels < 2 { gapPixels = 2 }
            if gapPixels % 2 == 1 { gapPixels += 1 }
            gap = CGFloat(gapPixels) / scale
        }
        return gap
    }

    private static func dotRects(cells: [(col: Int, row: Int)],
                                 size: CGSize,
                                 minimumGap: CGFloat = 0,
                                 scale: CGFloat = 0) -> [(rect: CGRect, row: Int)] {
        let (cell, offsetX, offsetY) = grid(size: size, scale: scale)
        let inset = dotGap(cell: cell, minimumGap: minimumGap, scale: scale) / 2
        return cells.map { c in
            let rect = cellRect(col: c.col, row: c.row, cell: cell,
                                offsetX: offsetX, offsetY: offsetY)
                .insetBy(dx: inset, dy: inset)
            return (rect, c.row)
        }
    }

    /// Banner variant: the same crop as the bar, without the halo.
    static func drawBanner(frame: Int, in context: CGContext, pixels: CGSize, palette: [NSColor]) {
        let index = min(max(frame, 0), frames.count - 1)
        draw(cells: frames[index], in: context,
             window: barWindow,
             cell: CGFloat(pixels.height) / barWindow.height,
             palette: palette)
    }

    /// Halo of the bar icon: the silhouette blurred into a soft dark
    /// glow, full strength around the pet and reduced to a faint tint
    /// inside it, so the dots read over any bar background without a
    /// solid fill. The banner draws no halo at all.
    private static func blurBehind(_ glyph: [(col: Int, row: Int)],
                                   in context: CGContext,
                                   pixels: CGSize,
                                   cell: CGFloat) {
        let canvas = CGRect(origin: .zero, size: pixels)
        // The glow carrier: the silhouette blurred into a soft blob.
        fill(silhouette: glyph, in: context, window: barWindow, cell: cell,
             color: NSColor.black.withAlphaComponent(0.65))
        guard let dark = context.makeImage() else { return }
        context.clear(canvas)
        // The split mask: the same silhouette in white. CIBlendWithMask
        // keys on the mask's luminance, and the fill above is black.
        fill(silhouette: glyph, in: context, window: barWindow, cell: cell,
             color: NSColor.white)
        guard let white = context.makeImage() else { return }
        context.clear(canvas)
        guard let halo = gaussianBlur(CIImage(cgImage: dark), radius: cell * 0.8),
              let mask = gaussianBlur(CIImage(cgImage: white), radius: cell * 0.35)
        else { return }
        // The interior share of the glow, fainter than the outside.
        let tint = CIFilter.colorMatrix()
        tint.inputImage = halo
        tint.aVector = CIVector(x: 0, y: 0, z: 0, w: 0.4)
        guard let interior = tint.outputImage else { return }
        // Full glow outside the feathered mask, faint glow inside it.
        let blend = CIFilter.blendWithMask()
        blend.inputImage = interior
        blend.backgroundImage = halo
        blend.maskImage = mask
        guard let output = blend.outputImage,
              let haloImage = PetRenderCache.ciContext.createCGImage(output, from: canvas) else { return }
        context.draw(haloImage, in: canvas)
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
        let dot = cell * 0.85
        let inset = (cell - dot) / 2
        let marginX = (square - CGFloat(maxCol - minCol + 1)) / 2
        let marginY = (square - CGFloat(maxRow - minRow + 1)) / 2
        let height = window.height * cell
        for c in glyph {
            let x = (marginX + CGFloat(c.col - minCol) - window.minX) * cell + inset
            let top = (marginY + CGFloat(c.row - minRow) - window.minY) * cell + inset
            let rect = CGRect(x: x, y: height - top - dot, width: dot, height: dot)
            context.setFillColor(palette[min(4, c.row * 5 / gridH)].cgColor)
            context.fill(rect)
        }
    }
}

/// The animated pet glyphs: the petit chat, and the chonk that Vibe shows
/// when the active model is "Le Chonk".
enum BarPet: String, Codable, CaseIterable, Identifiable, Sendable {
    case chaton
    case chonk

    var id: String { rawValue }

    var frameCount: Int {
        switch self {
        case .chaton: return Chaton.transitions.count + 1
        case .chonk: return Chonk.transitions.count + 1
        }
    }

    /// The pose the pet freezes on when it does not move: head down, eyes
    /// closed for the chaton; for the chonk the reference lying pose, on
    /// which its cycle closes.
    var restFrame: Int {
        switch self {
        case .chaton: return 14
        case .chonk: return frameCount - 1
        }
    }

    /// Next state in the cycle. The animation is periodic on states
    /// 1...N: after the last state, the first transition brings back the
    /// second one. State 0 is only the departure pose.
    func nextFrame(after frame: Int) -> Int {
        frame == frameCount - 1 ? 1 : frame + 1
    }

    /// The bar/banner crop of this pet's square.
    var barWindow: CGRect {
        switch self {
        case .chaton: return Chaton.barWindow
        case .chonk: return Chonk.barWindow
        }
    }

    var gridHeight: Int {
        switch self {
        case .chaton: return Chaton.gridH
        case .chonk: return Chonk.gridH
        }
    }

    func visibleDots(frame: Int) -> Set<Int> {
        let index = min(max(frame, 0), frameCount - 1)
        switch self {
        case .chaton: return Set(Chaton.frames[index].map(Chaton.key))
        case .chonk: return Set(Chonk.frames[index].map(Chonk.key))
        }
    }

    func dotSlots(size: CGSize) -> [(id: Int, rect: CGRect, row: Int)] {
        switch self {
        case .chaton: return Chaton.dotSlots(size: size)
        case .chonk: return Chonk.dotSlots(size: size)
        }
    }

    func drawBar(frame: Int, in context: CGContext, pixels: CGSize, palette: [NSColor]) {
        switch self {
        case .chaton: Chaton.drawBar(frame: frame, in: context, pixels: pixels, palette: palette)
        case .chonk: Chonk.drawBar(frame: frame, in: context, pixels: pixels, palette: palette)
        }
    }

    func drawBanner(frame: Int, in context: CGContext, pixels: CGSize, palette: [NSColor]) {
        switch self {
        case .chaton: Chaton.drawBanner(frame: frame, in: context, pixels: pixels, palette: palette)
        case .chonk: Chonk.drawBanner(frame: frame, in: context, pixels: pixels, palette: palette)
        }
    }
}
