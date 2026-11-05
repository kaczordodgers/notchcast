import CoreGraphics

enum NotchcastLauncherGeometry {
    /// The palette's top-left anchor on the frame the island grew into: the same frame, so the two read as one.
    static func anchor(launcherFrame: CGRect?, width: CGFloat) -> CGPoint? {
        guard let launcherFrame else { return nil }
        return CGPoint(x: launcherFrame.midX - width / 2, y: launcherFrame.maxY)
    }
}
