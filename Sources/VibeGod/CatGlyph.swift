import SwiftUI
import AppKit

/// Shared geometry of the cat silhouette, in a 0-1 coordinate space.
func catPath(w: CGFloat, h: CGFloat) -> Path {
    Path { p in
        // Left ear
        p.move(to: CGPoint(x: 0.20 * w, y: 0.46 * h))
        p.addLine(to: CGPoint(x: 0.22 * w, y: 0.04 * h))
        p.addLine(to: CGPoint(x: 0.47 * w, y: 0.30 * h))
        p.closeSubpath()
        // Right ear
        p.move(to: CGPoint(x: 0.80 * w, y: 0.46 * h))
        p.addLine(to: CGPoint(x: 0.78 * w, y: 0.04 * h))
        p.addLine(to: CGPoint(x: 0.53 * w, y: 0.30 * h))
        p.closeSubpath()
        // Head
        p.addEllipse(in: CGRect(x: 0.08 * w, y: 0.26 * h,
                                width: 0.84 * w, height: 0.70 * h))
    }
}

/// Cat silhouette as a regular SwiftUI view (window, previews).
struct CatGlyph: View {
    var body: some View {
        GeometryReader { geo in
            catPath(w: geo.size.width, h: geo.size.height).fill()
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
            context.addPath(catPath(w: size, h: size).cgPath)
            context.fillPath()
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
