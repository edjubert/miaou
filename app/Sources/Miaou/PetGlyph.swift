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
/// even gap. Each glyph's grid height divides the rows into five palette
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
enum BarPet: String, CaseIterable, Identifiable {
    case chaton
    case chonk

    var id: String { rawValue }

    var frameCount: Int {
        switch self {
        case .chaton: return Chaton.frames.count
        case .chonk: return Chonk.frames.count
        }
    }

    /// The pose the pet freezes on when it does not move: head down, eyes
    /// closed for the chaton; for the chonk the reference lying pose, on
    /// which its cycle closes.
    var restFrame: Int {
        switch self {
        case .chaton: return 14
        case .chonk: return Chonk.frames.count - 1
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
