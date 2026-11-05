import AppKit

@MainActor
enum NotchcastLauncherPlacement {
    static var isActive: Bool {
        NotchcastPreferences.shared.isOn(.island)
            && NotchcastPreferences.shared.isOn(.launcherFromIsland)
    }

    /// The palette's anchor over the island grown into its frame; nil leaves upstream's own placement.
    static func anchor(on screen: NSScreen, width: CGFloat) -> CGPoint? {
        guard isActive else { return nil }
        let collapsed = AppCore.shared.paletteCoordinator.paletteIsCollapsed
        return NotchcastLauncherGeometry.anchor(
            launcherFrame: IslandController.shared.growLauncher(on: screen, collapsed: collapsed), width: width)
    }
}
