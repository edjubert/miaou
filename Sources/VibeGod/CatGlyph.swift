import SwiftUI
import AppKit

/// Cat silhouette from Material Design Icons ("cat", mdi-cat),
/// Pictogrammers, Apache 2.0 (https://pictogrammers.com).
/// Original viewBox 0 0 24 24; arcs converted to cubic beziers.
/// Eyes and muzzle are cut out by opposite-winding subpaths, so fill
/// with the nonzero winding rule (SwiftUI default).
/// Coordinates are in the original 24-unit space, scaled by `s`.
func mdiCatPath(size: CGFloat) -> Path {
    let s = size / 24.0
    var p = Path()
    p.move(to: CGPoint(x: 12 * s, y: 8 * s))
    p.addLine(to: CGPoint(x: 10.67 * s, y: 8.09 * s))
    p.addCurve(to: CGPoint(x: 5 * s, y: 4.5 * s), control1: CGPoint(x: 9.81 * s, y: 7.07 * s), control2: CGPoint(x: 7.4 * s, y: 4.5 * s))
    p.addCurve(to: CGPoint(x: 4.96 * s, y: 11.41 * s), control1: CGPoint(x: 5 * s, y: 4.5 * s), control2: CGPoint(x: 3.03 * s, y: 7.46 * s))
    p.addCurve(to: CGPoint(x: 4 * s, y: 13.66 * s), control1: CGPoint(x: 4.41 * s, y: 12.24 * s), control2: CGPoint(x: 4.07 * s, y: 12.67 * s))
    p.addLine(to: CGPoint(x: 2.07 * s, y: 13.95 * s))
    p.addLine(to: CGPoint(x: 2.28 * s, y: 14.93 * s))
    p.addLine(to: CGPoint(x: 4.04 * s, y: 14.67 * s))
    p.addLine(to: CGPoint(x: 4.18 * s, y: 15.38 * s))
    p.addLine(to: CGPoint(x: 2.61 * s, y: 16.32 * s))
    p.addLine(to: CGPoint(x: 3.08 * s, y: 17.21 * s))
    p.addLine(to: CGPoint(x: 4.53 * s, y: 16.32 * s))
    p.addCurve(to: CGPoint(x: 12 * s, y: 20 * s), control1: CGPoint(x: 5.68 * s, y: 18.76 * s), control2: CGPoint(x: 8.59 * s, y: 20 * s))
    p.addCurve(to: CGPoint(x: 19.47 * s, y: 16.32 * s), control1: CGPoint(x: 15.41 * s, y: 20 * s), control2: CGPoint(x: 18.32 * s, y: 18.76 * s))
    p.addLine(to: CGPoint(x: 20.92 * s, y: 17.21 * s))
    p.addLine(to: CGPoint(x: 21.39 * s, y: 16.32 * s))
    p.addLine(to: CGPoint(x: 19.82 * s, y: 15.38 * s))
    p.addLine(to: CGPoint(x: 19.96 * s, y: 14.67 * s))
    p.addLine(to: CGPoint(x: 21.72 * s, y: 14.93 * s))
    p.addLine(to: CGPoint(x: 21.93 * s, y: 13.95 * s))
    p.addLine(to: CGPoint(x: 20 * s, y: 13.66 * s))
    p.addCurve(to: CGPoint(x: 19.04 * s, y: 11.41 * s), control1: CGPoint(x: 19.93 * s, y: 12.67 * s), control2: CGPoint(x: 19.59 * s, y: 12.24 * s))
    p.addCurve(to: CGPoint(x: 19 * s, y: 4.5 * s), control1: CGPoint(x: 20.97 * s, y: 7.46 * s), control2: CGPoint(x: 19 * s, y: 4.5 * s))
    p.addCurve(to: CGPoint(x: 13.33 * s, y: 8.09 * s), control1: CGPoint(x: 16.6 * s, y: 4.5 * s), control2: CGPoint(x: 14.19 * s, y: 7.07 * s))
    p.addLine(to: CGPoint(x: 12 * s, y: 8 * s))
    p.move(to: CGPoint(x: 9 * s, y: 11 * s))
    p.addCurve(to: CGPoint(x: 10 * s, y: 12 * s), control1: CGPoint(x: 9.5523 * s, y: 11 * s), control2: CGPoint(x: 10 * s, y: 11.4477 * s))
    p.addCurve(to: CGPoint(x: 9 * s, y: 13 * s), control1: CGPoint(x: 10 * s, y: 12.5523 * s), control2: CGPoint(x: 9.5523 * s, y: 13 * s))
    p.addCurve(to: CGPoint(x: 8 * s, y: 12 * s), control1: CGPoint(x: 8.4477 * s, y: 13 * s), control2: CGPoint(x: 8 * s, y: 12.5523 * s))
    p.addCurve(to: CGPoint(x: 9 * s, y: 11 * s), control1: CGPoint(x: 8 * s, y: 11.4477 * s), control2: CGPoint(x: 8.4477 * s, y: 11 * s))
    p.move(to: CGPoint(x: 15 * s, y: 11 * s))
    p.addCurve(to: CGPoint(x: 16 * s, y: 12 * s), control1: CGPoint(x: 15.5523 * s, y: 11 * s), control2: CGPoint(x: 16 * s, y: 11.4477 * s))
    p.addCurve(to: CGPoint(x: 15 * s, y: 13 * s), control1: CGPoint(x: 16 * s, y: 12.5523 * s), control2: CGPoint(x: 15.5523 * s, y: 13 * s))
    p.addCurve(to: CGPoint(x: 14 * s, y: 12 * s), control1: CGPoint(x: 14.4477 * s, y: 13 * s), control2: CGPoint(x: 14 * s, y: 12.5523 * s))
    p.addCurve(to: CGPoint(x: 15 * s, y: 11 * s), control1: CGPoint(x: 14 * s, y: 11.4477 * s), control2: CGPoint(x: 14.4477 * s, y: 11 * s))
    p.move(to: CGPoint(x: 11 * s, y: 14 * s))
    p.addLine(to: CGPoint(x: 13 * s, y: 14 * s))
    p.addLine(to: CGPoint(x: 12.3 * s, y: 15.39 * s))
    p.addCurve(to: CGPoint(x: 13.75 * s, y: 16.5 * s), control1: CGPoint(x: 12.5 * s, y: 16.03 * s), control2: CGPoint(x: 13.06 * s, y: 16.5 * s))
    p.addCurve(to: CGPoint(x: 15.25 * s, y: 15 * s), control1: CGPoint(x: 14.5784 * s, y: 16.5 * s), control2: CGPoint(x: 15.25 * s, y: 15.8284 * s))
    p.addLine(to: CGPoint(x: 15.75 * s, y: 15 * s))
    p.addCurve(to: CGPoint(x: 13.75 * s, y: 17 * s), control1: CGPoint(x: 15.75 * s, y: 16.1046 * s), control2: CGPoint(x: 14.8546 * s, y: 17 * s))
    p.addCurve(to: CGPoint(x: 12 * s, y: 16 * s), control1: CGPoint(x: 13 * s, y: 17 * s), control2: CGPoint(x: 12.35 * s, y: 16.59 * s))
    p.addLine(to: CGPoint(x: 12 * s, y: 16 * s))
    p.addLine(to: CGPoint(x: 12 * s, y: 16 * s))
    p.addCurve(to: CGPoint(x: 10.25 * s, y: 17 * s), control1: CGPoint(x: 11.65 * s, y: 16.59 * s), control2: CGPoint(x: 11 * s, y: 17 * s))
    p.addCurve(to: CGPoint(x: 8.25 * s, y: 15 * s), control1: CGPoint(x: 9.1454 * s, y: 17 * s), control2: CGPoint(x: 8.25 * s, y: 16.1046 * s))
    p.addLine(to: CGPoint(x: 8.75 * s, y: 15 * s))
    p.addCurve(to: CGPoint(x: 10.25 * s, y: 16.5 * s), control1: CGPoint(x: 8.75 * s, y: 15.8284 * s), control2: CGPoint(x: 9.4216 * s, y: 16.5 * s))
    p.addCurve(to: CGPoint(x: 11.7 * s, y: 15.39 * s), control1: CGPoint(x: 10.94 * s, y: 16.5 * s), control2: CGPoint(x: 11.5 * s, y: 16.03 * s))
    p.addLine(to: CGPoint(x: 11 * s, y: 14 * s))
    p.closeSubpath()
    return p
}

/// Cat silhouette as a regular SwiftUI view (window, previews).
struct CatGlyph: View {
    var body: some View {
        GeometryReader { geo in
            mdiCatPath(size: min(geo.size.width, geo.size.height)).fill()
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
            context.addPath(mdiCatPath(size: size).cgPath)
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
