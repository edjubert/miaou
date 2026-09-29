import SwiftUI

/// Minimal cat-head silhouette used as the menu bar icon.
/// Drawn as a Path so it renders in template style and scales to any size.
struct CatGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
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
            .fill()
        }
    }
}

#Preview("Cat glyph") {
    CatGlyph()
        .frame(width: 64, height: 64)
        .padding()
}
