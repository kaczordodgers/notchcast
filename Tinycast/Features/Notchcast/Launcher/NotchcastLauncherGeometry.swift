import CoreGraphics

enum NotchcastLauncherGeometry {
    /// The launcher is part of the island: centred on it, its top where the island meets the screen's top (under the
    /// notch, or level with the monitor pill's top), so the black grows straight into it.
    static func anchor(attachment: CGRect?, width: CGFloat, active: Bool) -> CGPoint? {
        guard active, let attachment else { return nil }
        return CGPoint(x: attachment.midX - width / 2, y: attachment.maxY)
    }
}
