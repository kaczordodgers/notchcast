import AppKit

@MainActor
enum NotchcastLauncherPlacement {
    static var isActive: Bool {
        NotchcastPreferences.shared.isOn(.island)
            && NotchcastPreferences.shared.isOn(.launcherFromIsland)
    }

    static func anchor(on screen: NSScreen, width: CGFloat) -> CGPoint? {
        let frame = NotchcastLauncherSurface.preferredScreen?.frame ?? screen.frame
        let island = NSApp.windows.compactMap { $0 as? IslandPanel }.first { $0.displayFrame == frame }
        return NotchcastLauncherGeometry.anchor(
            attachment: island?.launcherAttachment, width: width, active: isActive)
    }

    /// The island a launcher at `frame` hangs from, by the same rule `anchor` placed it with.
    static func island(hosting frame: CGRect, among panels: [IslandPanel]) -> IslandPanel? {
        guard isActive else { return nil }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return panels.first { $0.displayFrame.contains(center) && $0.launcherAttachment != nil }
    }

    /// An open island gives way to a launcher hung from it or one it covers or touches; elsewhere it stays.
    static func displaces(_ island: IslandPanel, launcher: CGRect, host: IslandPanel?) -> Bool {
        island === host || !island.openBodyFrame.intersection(launcher).isNull
    }
}
