import CoreGraphics

enum NotchcastLauncherGeometry {
    static let launcherGap: CGFloat = 8

    static func anchor(islandFrame: CGRect?, width: CGFloat, active: Bool) -> CGPoint? {
        guard active, let islandFrame else { return nil }
        return CGPoint(x: islandFrame.midX - width / 2, y: islandFrame.minY - launcherGap)
    }
}
