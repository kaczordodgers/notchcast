import CoreGraphics

enum NotchcastLauncherGeometry {
    /// `Theme.Spacing.md`, restated: the placement harness compiles this file without `Theme`.
    static let gap: CGFloat = 8

    /// The launcher hangs under the island, centred on it, a gap below so its glass never meets the black.
    static func anchor(attachment: CGRect?, width: CGFloat, active: Bool) -> CGPoint? {
        guard active, let attachment else { return nil }
        return CGPoint(x: attachment.midX - width / 2, y: attachment.minY - gap)
    }
}
