import CoreGraphics

enum NotchcastLauncherGeometry {
    static let monitorPillHeight: CGFloat = 28
    static let launcherGap: CGFloat = 8

    static func islandBottom(frame: CGRect, safeAreaTop: CGFloat, auxiliaryLeft: CGRect?) -> CGFloat {
        frame.maxY - (safeAreaTop > 0 ? safeAreaTop : auxiliaryLeft?.height ?? monitorPillHeight)
    }

    static func anchor(
        frame: CGRect, safeAreaTop: CGFloat, auxiliaryLeft: CGRect?, auxiliaryRight: CGRect?,
        width: CGFloat, active: Bool, default upstream: CGPoint
    ) -> CGPoint {
        guard active else { return upstream }
        let centerX: CGFloat
        if let auxiliaryLeft, let auxiliaryRight {
            centerX = (auxiliaryLeft.maxX + auxiliaryRight.minX) / 2
        } else {
            centerX = frame.midX
        }
        return CGPoint(
            x: centerX - width / 2,
            y: islandBottom(frame: frame, safeAreaTop: safeAreaTop, auxiliaryLeft: auxiliaryLeft)
                - launcherGap)
    }
}
