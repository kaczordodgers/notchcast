import AppKit

@MainActor
enum NotchcastLauncherPlacement {
    static var isActive: Bool {
        NotchcastPreferences.shared.isOn(.island)
            && NotchcastPreferences.shared.isOn(.launcherFromIsland)
    }

    static func anchor(on screen: NSScreen, width: CGFloat) -> CGPoint? {
        let island = NSApp.windows.compactMap { $0 as? IslandPanel }
            .first { $0.displayFrame == screen.frame }
        return NotchcastLauncherGeometry.anchor(
            islandFrame: island?.launcherPlacementFrame, width: width, active: isActive)
    }
}
