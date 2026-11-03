import CoreGraphics

enum NotchcastLauncherGeometry {
    // The island pack will own this height at integration.
    static let monitorPillHeight: CGFloat = 28
    static let launcherGap: CGFloat = 8

    static func islandBottom(frame: CGRect, safeAreaTop: CGFloat, auxiliaryLeft: CGRect?) -> CGFloat {
        frame.maxY - (safeAreaTop > 0 ? safeAreaTop : auxiliaryLeft?.height ?? monitorPillHeight)
    }

    static func anchor(
        frame: CGRect, safeAreaTop: CGFloat, auxiliaryLeft: CGRect?, auxiliaryRight: CGRect?,
        width: CGFloat, active: Bool
    ) -> CGPoint? {
        guard active else { return nil }
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
