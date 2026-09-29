import SwiftUI
import AppKit

/// Cat silhouette from Font Awesome Free ("cat", solid), the glyph
/// referenced by Nerd Fonts as fa-cat (U+EEED). Icons CC BY 4.0,
/// https://fontawesome.com. Original viewBox 0 0 576 512; relative
/// commands resolved, implicit repetitions expanded, arcs converted to
/// cubic beziers. Scaled and centered into the square given by `size`.
func faCatPath(size: CGFloat) -> Path {
    let s = size / 576.0
    let ox = (size - 576.0 * s) / 2
    let oy = (size - 512.0 * s) / 2
    var p = Path()
    p.move(to: CGPoint(x: ox + 320 * s, y: oy + 192 * s))
    p.addLine(to: CGPoint(x: ox + 337.1 * s, y: oy + 192 * s))
    p.addCurve(to: CGPoint(x: ox + 448 * s, y: oy + 256 * s), control1: CGPoint(x: ox + 359.2 * s, y: oy + 230.3 * s), control2: CGPoint(x: ox + 400.6 * s, y: oy + 256 * s))
    p.addCurve(to: CGPoint(x: ox + 480 * s, y: oy + 252 * s), control1: CGPoint(x: ox + 459 * s, y: oy + 256 * s), control2: CGPoint(x: ox + 469.8 * s, y: oy + 254.6 * s))
    p.addLine(to: CGPoint(x: ox + 480 * s, y: oy + 256 * s))
    p.addLine(to: CGPoint(x: ox + 480 * s, y: oy + 288 * s))
    p.addLine(to: CGPoint(x: ox + 480 * s, y: oy + 480 * s))
    p.addCurve(to: CGPoint(x: ox + 448 * s, y: oy + 512 * s), control1: CGPoint(x: ox + 480 * s, y: oy + 497.7 * s), control2: CGPoint(x: ox + 465.7 * s, y: oy + 512 * s))
    p.addCurve(to: CGPoint(x: ox + 416 * s, y: oy + 480 * s), control1: CGPoint(x: ox + 430.3 * s, y: oy + 512 * s), control2: CGPoint(x: ox + 416 * s, y: oy + 497.7 * s))
    p.addLine(to: CGPoint(x: ox + 416 * s, y: oy + 339.2 * s))
    p.addLine(to: CGPoint(x: ox + 280 * s, y: oy + 448 * s))
    p.addLine(to: CGPoint(x: ox + 336 * s, y: oy + 448 * s))
    p.addCurve(to: CGPoint(x: ox + 368 * s, y: oy + 480 * s), control1: CGPoint(x: ox + 353.7 * s, y: oy + 448 * s), control2: CGPoint(x: ox + 368 * s, y: oy + 462.3 * s))
    p.addCurve(to: CGPoint(x: ox + 336 * s, y: oy + 512 * s), control1: CGPoint(x: ox + 368 * s, y: oy + 497.7 * s), control2: CGPoint(x: ox + 353.7 * s, y: oy + 512 * s))
    p.addLine(to: CGPoint(x: ox + 192 * s, y: oy + 512 * s))
    p.addCurve(to: CGPoint(x: ox + 96 * s, y: oy + 416 * s), control1: CGPoint(x: ox + 139 * s, y: oy + 512 * s), control2: CGPoint(x: ox + 96 * s, y: oy + 469 * s))
    p.addLine(to: CGPoint(x: ox + 96 * s, y: oy + 192.5 * s))
    p.addCurve(to: CGPoint(x: ox + 68 * s, y: oy + 160.7 * s), control1: CGPoint(x: ox + 96 * s, y: oy + 176.4 * s), control2: CGPoint(x: ox + 84 * s, y: oy + 162.7 * s))
    p.addLine(to: CGPoint(x: ox + 60.1 * s, y: oy + 159.7 * s))
    p.addCurve(to: CGPoint(x: ox + 32.3 * s, y: oy + 124 * s), control1: CGPoint(x: ox + 42.6 * s, y: oy + 157.5 * s), control2: CGPoint(x: ox + 30.1 * s, y: oy + 141.5 * s))
    p.addCurve(to: CGPoint(x: ox + 68 * s, y: oy + 96.2 * s), control1: CGPoint(x: ox + 34.5 * s, y: oy + 106.5 * s), control2: CGPoint(x: ox + 50.5 * s, y: oy + 94 * s))
    p.addLine(to: CGPoint(x: ox + 75.9 * s, y: oy + 97.2 * s))
    p.addCurve(to: CGPoint(x: ox + 160 * s, y: oy + 192.5 * s), control1: CGPoint(x: ox + 123.9 * s, y: oy + 103.2 * s), control2: CGPoint(x: ox + 160 * s, y: oy + 144 * s))
    p.addLine(to: CGPoint(x: ox + 160 * s, y: oy + 277.8 * s))
    p.addCurve(to: CGPoint(x: ox + 320 * s, y: oy + 192 * s), control1: CGPoint(x: ox + 194.4 * s, y: oy + 226.1 * s), control2: CGPoint(x: ox + 253.2 * s, y: oy + 192 * s))
    p.closeSubpath()
    p.move(to: CGPoint(x: ox + 480 * s, y: oy + 218.5 * s))
    p.addCurve(to: CGPoint(x: ox + 480 * s, y: oy + 218.5 * s), control1: CGPoint(x: ox + 480 * s, y: oy + 218.5 * s), control2: CGPoint(x: ox + 480 * s, y: oy + 218.5 * s))
    p.addCurve(to: CGPoint(x: ox + 448 * s, y: oy + 224 * s), control1: CGPoint(x: ox + 470 * s, y: oy + 222 * s), control2: CGPoint(x: ox + 459.2 * s, y: oy + 224 * s))
    p.addCurve(to: CGPoint(x: ox + 376.4 * s, y: oy + 192 * s), control1: CGPoint(x: ox + 419.6 * s, y: oy + 224 * s), control2: CGPoint(x: ox + 394 * s, y: oy + 211.6 * s))
    p.addCurve(to: CGPoint(x: ox + 376.4 * s, y: oy + 192 * s), control1: CGPoint(x: ox + 376.4 * s, y: oy + 192 * s), control2: CGPoint(x: ox + 376.4 * s, y: oy + 192 * s))
    p.addCurve(to: CGPoint(x: ox + 366.5 * s, y: oy + 178.8 * s), control1: CGPoint(x: ox + 372.7 * s, y: oy + 187.9 * s), control2: CGPoint(x: ox + 369.4 * s, y: oy + 183.5 * s))
    p.addCurve(to: CGPoint(x: ox + 352 * s, y: oy + 128 * s), control1: CGPoint(x: ox + 357.3 * s, y: oy + 164 * s), control2: CGPoint(x: ox + 352 * s, y: oy + 146.6 * s))
    p.addCurve(to: CGPoint(x: ox + 352 * s, y: oy + 128 * s), control1: CGPoint(x: ox + 352 * s, y: oy + 128 * s), control2: CGPoint(x: ox + 352 * s, y: oy + 128 * s))
    p.addLine(to: CGPoint(x: ox + 352 * s, y: oy + 32 * s))
    p.addLine(to: CGPoint(x: ox + 352 * s, y: oy + 12 * s))
    p.addLine(to: CGPoint(x: ox + 352 * s, y: oy + 10.7 * s))
    p.addCurve(to: CGPoint(x: ox + 362.6 * s, y: oy + 0 * s), control1: CGPoint(x: ox + 352 * s, y: oy + 4.8 * s), control2: CGPoint(x: ox + 356.7 * s, y: oy + 0.1 * s))
    p.addLine(to: CGPoint(x: ox + 362.8 * s, y: oy + 0 * s))
    p.addCurve(to: CGPoint(x: ox + 371.2 * s, y: oy + 4.2 * s), control1: CGPoint(x: ox + 366.1 * s, y: oy + 0 * s), control2: CGPoint(x: ox + 369.2 * s, y: oy + 1.6 * s))
    p.addCurve(to: CGPoint(x: ox + 371.2 * s, y: oy + 4.3 * s), control1: CGPoint(x: ox + 371.2 * s, y: oy + 4.2 * s), control2: CGPoint(x: ox + 371.2 * s, y: oy + 4.2 * s))
    p.addLine(to: CGPoint(x: ox + 384 * s, y: oy + 21.3 * s))
    p.addLine(to: CGPoint(x: ox + 411.2 * s, y: oy + 57.6 * s))
    p.addLine(to: CGPoint(x: ox + 416 * s, y: oy + 64 * s))
    p.addLine(to: CGPoint(x: ox + 480 * s, y: oy + 64 * s))
    p.addLine(to: CGPoint(x: ox + 484.8 * s, y: oy + 57.6 * s))
    p.addLine(to: CGPoint(x: ox + 512 * s, y: oy + 21.3 * s))
    p.addLine(to: CGPoint(x: ox + 524.8 * s, y: oy + 4.3 * s))
    p.addCurve(to: CGPoint(x: ox + 524.8 * s, y: oy + 4.2 * s), control1: CGPoint(x: ox + 524.8 * s, y: oy + 4.3 * s), control2: CGPoint(x: ox + 524.8 * s, y: oy + 4.3 * s))
    p.addCurve(to: CGPoint(x: ox + 533.2 * s, y: oy + 0 * s), control1: CGPoint(x: ox + 526.8 * s, y: oy + 1.6 * s), control2: CGPoint(x: ox + 529.9 * s, y: oy + 0 * s))
    p.addLine(to: CGPoint(x: ox + 533.4 * s, y: oy + 0 * s))
    p.addCurve(to: CGPoint(x: ox + 544 * s, y: oy + 10.7 * s), control1: CGPoint(x: ox + 539.3 * s, y: oy + 0.1 * s), control2: CGPoint(x: ox + 544 * s, y: oy + 4.8 * s))
    p.addLine(to: CGPoint(x: ox + 544 * s, y: oy + 12 * s))
    p.addLine(to: CGPoint(x: ox + 544 * s, y: oy + 32 * s))
    p.addLine(to: CGPoint(x: ox + 544 * s, y: oy + 128 * s))
    p.addCurve(to: CGPoint(x: ox + 531.4 * s, y: oy + 175.6 * s), control1: CGPoint(x: ox + 544 * s, y: oy + 145.3 * s), control2: CGPoint(x: ox + 539.4 * s, y: oy + 161.6 * s))
    p.addCurve(to: CGPoint(x: ox + 480 * s, y: oy + 218.5 * s), control1: CGPoint(x: ox + 520.1 * s, y: oy + 195.4 * s), control2: CGPoint(x: ox + 501.8 * s, y: oy + 210.8 * s))
    p.closeSubpath()
    p.move(to: CGPoint(x: ox + 432 * s, y: oy + 128 * s))
    p.addCurve(to: CGPoint(x: ox + 416 * s, y: oy + 112 * s), control1: CGPoint(x: ox + 432 * s, y: oy + 119.1634 * s), control2: CGPoint(x: ox + 424.8366 * s, y: oy + 112 * s))
    p.addCurve(to: CGPoint(x: ox + 400 * s, y: oy + 128 * s), control1: CGPoint(x: ox + 407.1634 * s, y: oy + 112 * s), control2: CGPoint(x: ox + 400 * s, y: oy + 119.1634 * s))
    p.addCurve(to: CGPoint(x: ox + 416 * s, y: oy + 144 * s), control1: CGPoint(x: ox + 400 * s, y: oy + 136.8366 * s), control2: CGPoint(x: ox + 407.1634 * s, y: oy + 144 * s))
    p.addCurve(to: CGPoint(x: ox + 432 * s, y: oy + 128 * s), control1: CGPoint(x: ox + 424.8366 * s, y: oy + 144 * s), control2: CGPoint(x: ox + 432 * s, y: oy + 136.8366 * s))
    p.closeSubpath()
    p.move(to: CGPoint(x: ox + 480 * s, y: oy + 144 * s))
    p.addCurve(to: CGPoint(x: ox + 496 * s, y: oy + 128 * s), control1: CGPoint(x: ox + 488.8366 * s, y: oy + 144 * s), control2: CGPoint(x: ox + 496 * s, y: oy + 136.8366 * s))
    p.addCurve(to: CGPoint(x: ox + 480 * s, y: oy + 112 * s), control1: CGPoint(x: ox + 496 * s, y: oy + 119.1634 * s), control2: CGPoint(x: ox + 488.8366 * s, y: oy + 112 * s))
    p.addCurve(to: CGPoint(x: ox + 464 * s, y: oy + 128 * s), control1: CGPoint(x: ox + 471.1634 * s, y: oy + 112 * s), control2: CGPoint(x: ox + 464 * s, y: oy + 119.1634 * s))
    p.addCurve(to: CGPoint(x: ox + 480 * s, y: oy + 144 * s), control1: CGPoint(x: ox + 464 * s, y: oy + 136.8366 * s), control2: CGPoint(x: ox + 471.1634 * s, y: oy + 144 * s))
    p.closeSubpath()
    return p
}

/// Cat silhouette as a regular SwiftUI view (window, previews).
struct CatGlyph: View {
    var body: some View {
        GeometryReader { geo in
            faCatPath(size: min(geo.size.width, geo.size.height)).fill()
        }
    }
}

/// Menu bar labels render a limited view set (Text, Image), so the cat
/// is rasterized into colored NSImages: green while a Vibe session is
/// live, orange otherwise.
enum CatIcon {
    static let live = image(color: NSColor.systemGreen)
    static let idle = image(color: NSColor.systemOrange)

    private static func image(color: NSColor, size: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            color.setFill()
            context.translateBy(x: 0, y: size)
            context.scaleBy(x: 1, y: -1)
            context.addPath(faCatPath(size: size).cgPath)
            context.fillPath(using: .winding)
        }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

#Preview("Cat glyph") {
    CatGlyph()
        .frame(width: 64, height: 64)
        .padding()
}
