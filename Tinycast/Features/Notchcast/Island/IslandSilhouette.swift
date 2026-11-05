import CoreGraphics

enum IslandSilhouette {
    /// Corners scale with the silhouette's height up to a cap (after Vorssaint's notch, GPL-3.0-or-later): a strip
    /// as tall as the camera keeps the cutout's small corners, a tall open island the full ones.
    static let shoulderRatio: CGFloat = 0.19
    static let bottomRadiusRatio: CGFloat = 0.34

    static func shoulder(height: CGFloat, cap: CGFloat) -> CGFloat {
        min(max(0, cap), max(0, height) * shoulderRatio)
    }

    static func bottomRadius(height: CGFloat, cap: CGFloat) -> CGFloat {
        min(max(0, cap), max(0, height) * bottomRadiusRatio)
    }

    /// A shape hanging from the screen's top edge: flat on top with concave shoulders, rounded below. A `topRadius`
    /// rounds the top corners instead, for a capsule floating under the edge; a `bubble` adds a circle of that
    /// diameter `bubbleGap` to the right, for a second activity.
    static func path(in rect: CGRect, shoulder: CGFloat, bottomRadius: CGFloat, topRadius: CGFloat = 0,
                     bubble: CGFloat = 0, bubbleGap: CGFloat = 0) -> CGPath {
        let path = CGMutablePath()
        let bubble = min(max(0, bubble), rect.height)
        let body = bubble > 0 ? CGRect(x: rect.minX, y: rect.minY, width: max(0, rect.width - bubble - bubbleGap),
                                       height: rect.height) : rect
        path.addPath(bodyPath(in: body, shoulder: shoulder, bottomRadius: bottomRadius, topRadius: topRadius))
        if bubble > 0 {
            path.addEllipse(in: CGRect(x: rect.maxX - bubble, y: rect.midY - bubble / 2, width: bubble, height: bubble))
        }
        return path
    }

    private static func bodyPath(in rect: CGRect, shoulder: CGFloat, bottomRadius: CGFloat, topRadius: CGFloat) -> CGPath {
        let shoulder = min(max(0, shoulder), rect.width / 2, rect.height / 2)
        let radius = min(max(0, bottomRadius), (rect.width - shoulder * 2) / 2,
                         rect.height - shoulder)
        let top = shoulder > 0 ? 0 : min(max(0, topRadius), rect.width / 2, rect.height - radius)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        if top > 0 {
            path.move(to: CGPoint(x: rect.minX + top, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - top),
                              control: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - shoulder, y: rect.maxY - shoulder),
                              control: CGPoint(x: rect.maxX - shoulder, y: rect.maxY))
        }
        path.addLine(to: CGPoint(x: rect.maxX - shoulder, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - shoulder - radius, y: rect.minY),
                          control: CGPoint(x: rect.maxX - shoulder, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + shoulder + radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + shoulder, y: rect.minY + radius),
                          control: CGPoint(x: rect.minX + shoulder, y: rect.minY))
        if top > 0 {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - top))
            path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.maxY),
                              control: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.addLine(to: CGPoint(x: rect.minX + shoulder, y: rect.maxY - shoulder))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY),
                              control: CGPoint(x: rect.minX + shoulder, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}
