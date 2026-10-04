import AppKit

/// Icon style for the menu bar label.
enum BarIconStyle: String, CaseIterable, Identifiable {
    /// Brand colors while a session is live, grayscale otherwise.
    case session
    case color
    case grayscale
    /// The Chaton glyph, brand colors live, grayscale otherwise.
    case chaton

    var id: String { rawValue }

    var label: String {
        switch self {
        case .session: return "Session"
        case .color: return "Couleur"
        case .grayscale: return "Gris"
        case .chaton: return "Chaton"
        }
    }
}

/// One rectangle of a block glyph, in the shared 24x24 viewBox with the
/// SVG convention (y grows downward). `row` indexes the 5-color palettes.
typealias GlyphBlock = (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, row: Int)

/// Fills glyph blocks into a CG context whose origin is the bottom-left
/// corner of a `size`-point square.
func drawBlocks(_ blocks: [GlyphBlock], in context: CGContext, size: CGFloat, palette: [NSColor]) {
    let s = size / 24
    for b in blocks {
        let rect = CGRect(
            x: b.x * s,
            y: size - (b.y + b.h) * s,
            width: b.w * s,
            height: b.h * s
        )
        // setFillColor(cgColor), not NSColor.setFill(): a raw
        // CGContext has no current NSGraphicsContext to route through.
        context.setFillColor(palette[b.row].cgColor)
        context.fill(rect)
    }
}

/// Mistral logo: 12 blocks in 5 rows on the official 24x24 viewBox,
/// one color per row. Palettes run top to bottom. Source geometry:
/// https://assets.mistral.ai/icon.svg
enum MistralLogo {
    /// Brand colors, gold #FFD700 down to red #E10500.
    static let brand: [NSColor] = [
        NSColor(red: 1.000, green: 0.843, blue: 0.000, alpha: 1),
        NSColor(red: 1.000, green: 0.686, blue: 0.000, alpha: 1),
        NSColor(red: 1.000, green: 0.510, blue: 0.020, alpha: 1),
        NSColor(red: 0.980, green: 0.314, blue: 0.059, alpha: 1),
        NSColor(red: 0.882, green: 0.020, blue: 0.000, alpha: 1),
    ]

    /// Same light-to-dark gradient, desaturated.
    static let grayscale: [NSColor] = (0..<5).map {
        NSColor(white: 0.80 - CGFloat($0) * 0.16, alpha: 1)
    }

    /// Block rectangles in the 24x24 viewBox: (x, y, width, height, row).
    /// Coordinates follow the SVG convention (y grows downward); draw
    /// converts them to the context's bottom-left origin.
    static let blocks: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, row: Int)] = [
        (3.428, 3.4, 3.429, 3.428, 0),
        (17.142, 3.4, 3.43, 3.428, 0),
        (3.428, 6.828, 6.857, 3.429, 1),
        (13.714, 6.828, 6.857, 3.429, 1),
        (3.428, 10.258, 17.144, 3.428, 2),
        (3.428, 13.686, 3.429, 3.428, 3),
        (10.286, 13.686, 3.429, 3.428, 3),
        (17.142, 13.686, 3.43, 3.428, 3),
        (0, 17.114, 10.286, 3.429, 4),
        (13.714, 17.114, 10.286, 3.429, 4),
    ]

    /// Fills the blocks into a CG context whose origin is the bottom-left
    /// corner of a `size`-point square. Content stays vertically centered,
    /// as in the official viewBox.
    static func draw(in context: CGContext, size: CGFloat, palette: [NSColor]) {
        drawBlocks(blocks, in: context, size: size, palette: palette)
    }
}

/// Menu bar labels render a limited view set (Text, Image), so the logo
/// is rasterized into NSImages. Images are cached per style and state.
enum MistralIcon {
    static let barSize: CGFloat = 16

    private static var cache: [String: NSImage] = [:]

    static func image(style: BarIconStyle, live: Bool, frame: Int = 0) -> NSImage {
        let key = "\(style.rawValue)-\(live)-\(frame)"
        if let cached = cache[key] { return cached }
        let palette: [NSColor]
        let draw: (CGContext, CGFloat) -> Void
        switch style {
        case .color:
            palette = MistralLogo.brand
            draw = { MistralLogo.draw(in: $0, size: $1, palette: palette) }
        case .grayscale:
            palette = MistralLogo.grayscale
            draw = { MistralLogo.draw(in: $0, size: $1, palette: palette) }
        case .session:
            palette = live ? MistralLogo.brand : MistralLogo.grayscale
            draw = { MistralLogo.draw(in: $0, size: $1, palette: palette) }
        case .chaton:
            palette = live ? MistralLogo.brand : MistralLogo.grayscale
            draw = { Chaton.draw(frame: frame, in: $0, size: $1, palette: palette) }
        }
        let image = rasterize(draw: draw)
        cache[key] = image
        return image
    }

    /// Renders the glyph into a `pixels`-pixel bitmap backing a `barSize`
    /// point image, so it stays crisp on 2x/3x menu bars.
    private static func rasterize(draw: (CGContext, CGFloat) -> Void, pixels: Int = 64) -> NSImage {
        guard let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("could not create bitmap context")
        }
        draw(context, CGFloat(pixels))
        guard let cgImage = context.makeImage() else {
            fatalError("could not render bar icon")
        }
        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: barSize, height: barSize)
        )
        image.isTemplate = false
        return image
    }
}
