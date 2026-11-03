import AppKit

@MainActor
enum NotchcastLauncherPlacement {
    static var isActive: Bool {
        NotchcastPreferences.shared.isOn(.island)
            && NotchcastPreferences.shared.isOn(.launcherFromIsland)
    }

    static func anchor(on screen: NSScreen, width: CGFloat) -> CGPoint? {
        NotchcastLauncherGeometry.anchor(
            frame: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryLeft: screen.auxiliaryTopLeftArea,
            auxiliaryRight: screen.auxiliaryTopRightArea,
            width: width, active: isActive)
    }
}
