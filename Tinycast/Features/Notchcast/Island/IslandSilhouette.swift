import CoreGraphics

/// The island's whole outline: a body and one bubble. Every state, both shapes and the opening into the launcher
/// draw the same elements in the same order (a zero corner or a parked bubble is a degenerate curve, never a
/// missing one), so Core Animation morphs any outline into any other.
struct IslandOutline: Equatable, Sendable {
    var body: CGRect
    /// The concave flare where an attached body meets the screen's top edge.
    var shoulder: CGFloat = 0
    var bottomRadius: CGFloat = 0
    /// A detached body (the monitor pill, the launcher) rounds its top too.
    var topRadius: CGFloat = 0
    /// The second thing's bubble; parked as a point inside the body's trailing end when there is none.
    var bubble: CGRect?

    var parkedBubble: CGRect {
        bubble ?? CGRect(x: body.maxX - body.height / 2, y: body.midY, width: 0, height: 0)
    }

    var bounds: CGRect { bubble.map { body.union($0) } ?? body }

    /// Straight-line interpolation of every parameter, which is exactly what interpolating the path's points does.
    static func interpolate(_ from: Self, _ to: Self, progress: CGFloat) -> Self {
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * progress }
        func mix(_ a: CGRect, _ b: CGRect) -> CGRect {
            CGRect(x: mix(a.minX, b.minX), y: mix(a.minY, b.minY),
                   width: mix(a.width, b.width), height: mix(a.height, b.height))
        }
        return Self(body: mix(from.body, to.body), shoulder: mix(from.shoulder, to.shoulder),
                    bottomRadius: mix(from.bottomRadius, to.bottomRadius), topRadius: mix(from.topRadius, to.topRadius),
                    bubble: mix(from.parkedBubble, to.parkedBubble))
    }
}

enum IslandSilhouette {
    /// Corners scale with the silhouette's height up to a cap (after the notch Damian picked, GPL-3.0-or-later): a
    /// strip as tall as the camera keeps the cutout's small corners, a tall open island the full ones.
    static let shoulderRatio: CGFloat = 0.19
    static let bottomRadiusRatio: CGFloat = 0.34

    static func shoulder(height: CGFloat, cap: CGFloat) -> CGFloat {
        min(max(0, cap), max(0, height) * shoulderRatio)
    }

    static func bottomRadius(height: CGFloat, cap: CGFloat) -> CGFloat {
        min(max(0, cap), max(0, height) * bottomRadiusRatio)
    }

    static func path(in rect: CGRect, shoulder: CGFloat, bottomRadius: CGFloat) -> CGPath {
        path(IslandOutline(body: rect, shoulder: shoulder, bottomRadius: bottomRadius))
    }

    static func path(_ outline: IslandOutline) -> CGPath {
        let rect = outline.body
        let shoulder = min(max(0, outline.shoulder), rect.width / 2, rect.height / 2)
        let top = min(max(0, outline.topRadius), (rect.width - shoulder * 2) / 2, rect.height / 2)
        let radius = min(max(0, outline.bottomRadius), (rect.width - shoulder * 2) / 2,
                         rect.height - shoulder - top)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX + top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - top),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - shoulder, y: rect.maxY - top - shoulder),
                          control: CGPoint(x: rect.maxX - shoulder, y: rect.maxY - top))
        path.addLine(to: CGPoint(x: rect.maxX - shoulder, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - shoulder - radius, y: rect.minY),
                          control: CGPoint(x: rect.maxX - shoulder, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + shoulder + radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + shoulder, y: rect.minY + radius),
                          control: CGPoint(x: rect.minX + shoulder, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + shoulder, y: rect.maxY - top - shoulder))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - top),
                          control: CGPoint(x: rect.minX + shoulder, y: rect.maxY - top))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.maxY),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        path.addEllipse(in: outline.parkedBubble)
        return path
    }
}
