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

    static func path(in rect: CGRect, shoulder: CGFloat, bottomRadius: CGFloat) -> CGPath {
        let shoulder = min(max(0, shoulder), rect.width / 2, rect.height / 2)
        let radius = min(max(0, bottomRadius), (rect.width - shoulder * 2) / 2,
                         rect.height - shoulder)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - shoulder, y: rect.maxY - shoulder),
                          control: CGPoint(x: rect.maxX - shoulder, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - shoulder, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - shoulder - radius, y: rect.minY),
                          control: CGPoint(x: rect.maxX - shoulder, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + shoulder + radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + shoulder, y: rect.minY + radius),
                          control: CGPoint(x: rect.minX + shoulder, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + shoulder, y: rect.maxY - shoulder))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY),
                          control: CGPoint(x: rect.minX + shoulder, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
