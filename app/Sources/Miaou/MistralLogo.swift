import AppKit

/// Icon glyph for the menu bar label.
/// `label` lives in MiaouApp.swift: this file is also compiled standalone
/// by `make icon`, outside SPM, and must not reference Bundle.module.
enum BarIconStyle: String, CaseIterable, Identifiable {
    /// The Mistral logo.
    case logo
    /// The Chaton glyph.
    case chaton

    var id: String { rawValue }
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

/// Color mode shared by both glyphs and the banner.
enum ChatonColorMode: String, CaseIterable, Identifiable {
    /// Brand colors while a session is live, grayscale otherwise.
    case session
    case color
    case grayscale

    var id: String { rawValue }
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

    /// Same light-to-dark gradient, desaturated. The ramp stays close
    /// to white so the dark rows remain readable on a dark menu bar.
    static let grayscale: [NSColor] = (0..<5).map {
        NSColor(white: 0.95 - CGFloat($0) * 0.10, alpha: 1)
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

/// Menu bar labels render a limited view set (Text, Image), so the glyphs
/// are rasterized into NSImages. Images are cached per style, state and
/// frame.
enum MistralIcon {
    static let barSize: CGFloat = 16

    /// The chaton is wide: its bar image is not square. The window crop
    /// is 23 x 11 cells at 6 px each.
    static let chatonBarPoints = NSSize(width: barSize * 23 / 11, height: barSize)
    private static let chatonBarPixels = CGSize(width: 138, height: 66)
    private static let logoPixels: Int = 64

    /// Full-width banner of the menu window header: the chaton at the
    /// window width, with 2x backing to stay crisp.
    private static let bannerPoints = NSSize(width: 287.5, height: 137.5)
    private static let bannerPixels = CGSize(width: 575, height: 275)

    private static var cache: [String: NSImage] = [:]

    static func image(style: BarIconStyle,
                      live: Bool,
                      frame: Int = 0,
                      colorMode: ChatonColorMode = .session) -> NSImage {
        let key = "\(style.rawValue)-\(live)-\(frame)-\(colorMode.rawValue)"
        if let cached = cache[key] { return cached }
        let image: NSImage
        switch style {
        case .logo:
            let palette = palette(live: live, mode: colorMode)
            let pixels = logoPixels
            image = rasterize(pixels: CGSize(width: pixels, height: pixels), points: NSSize(width: barSize, height: barSize)) { context in
                MistralLogo.draw(in: context, size: CGFloat(pixels), palette: palette)
            }
        case .chaton:
            let palette = palette(live: live, mode: colorMode)
            let pixels = chatonBarPixels
            image = rasterize(pixels: pixels, points: chatonBarPoints) { context in
                Chaton.drawBar(frame: frame, in: context, pixels: pixels, palette: palette)
            }
        }
        cache[key] = image
        return image
    }

    /// Glyph palette for the selected color mode.
    static func palette(live: Bool, mode: ChatonColorMode) -> [NSColor] {
        switch mode {
        case .color: return MistralLogo.brand
        case .grayscale: return MistralLogo.grayscale
        case .session: return live ? MistralLogo.brand : MistralLogo.grayscale
        }
    }

    /// The animated banner of the menu window header.
    static func bannerImage(frame: Int, colorMode: ChatonColorMode = .session) -> NSImage {
        let key = "banner-\(frame)-\(colorMode.rawValue)"
        if let cached = cache[key] { return cached }
        let pixels = bannerPixels
        let palette = palette(live: true, mode: colorMode)
        let image = rasterize(pixels: pixels, points: bannerPoints) { context in
            Chaton.drawBanner(frame: frame, in: context, pixels: pixels, palette: palette)
        }
        cache[key] = image
        return image
    }

    /// Renders the glyph into a `pixels`-pixel bitmap backing a `points`
    /// point image, so it stays crisp on 2x/3x menu bars.
    private static func rasterize(pixels: CGSize, points: NSSize, draw: (CGContext) -> Void) -> NSImage {
        guard let context = CGContext(
            data: nil,
            width: Int(pixels.width),
            height: Int(pixels.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("could not create bitmap context")
        }
        draw(context)
        guard let cgImage = context.makeImage() else {
            fatalError("could not render bar icon")
        }
        let image = NSImage(
            cgImage: cgImage,
            size: points
        )
        image.isTemplate = false
        return image
    }
}
