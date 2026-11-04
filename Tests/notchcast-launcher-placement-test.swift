// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/NotchcastLauncherGeometry.swift
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/NotchcastLauncherPlacement.swift
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/IslandPanel+LauncherPlacement.swift
import AppKit
import QuartzCore

@MainActor
final class NotchcastPreferences {
    static let shared = NotchcastPreferences()
    var enabled: Set<NotchcastFeature> = [.island, .launcherFromIsland]
    func isOn(_ feature: NotchcastFeature) -> Bool { enabled.contains(feature) }
}

@MainActor
final class IslandPanel: NSPanel {
    var displayFrame: CGRect { frame }
    var shown = false
    var activeSpace = true
    override var isVisible: Bool { shown }
    override var isOnActiveSpace: Bool { activeSpace }
}

@main
@MainActor
struct NotchcastLauncherPlacementTests {
    static func main() {
        let notch = CGRect(x: -1070, y: 1248, width: 200, height: 32)
        func anchor(_ island: CGRect?) -> CGPoint? {
            NotchcastLauncherGeometry.anchor(
                islandFrame: island, width: 750, active: NotchcastLauncherPlacement.isActive)
        }
        assert(anchor(notch) == CGPoint(x: -1345, y: 1240))
        let message = CGRect(x: -1114, y: 1212, width: 288, height: 68)
        assert(anchor(message) == CGPoint(x: -1345, y: 1204))
        let externalPill = CGRect(x: 2470, y: 1049, width: 180, height: 31)
        assert(anchor(externalPill) == CGPoint(x: 2185, y: 1041))
        assert(anchor(nil) == nil)
        for feature in [NotchcastFeature.island, .launcherFromIsland] {
            NotchcastPreferences.shared.enabled.remove(feature)
            assert(anchor(notch) == nil)
            NotchcastPreferences.shared.enabled.insert(feature)
            assert(anchor(notch) != nil)
        }
        let panel = IslandPanel(contentRect: .zero, styleMask: .borderless,
                                backing: .buffered, defer: false)
        assert(panel.launcherPlacementFrame == nil)
        panel.setFrame(CGRect(x: 200, y: 300, width: 800, height: 500), display: false)
        let surface = NSView(frame: CGRect(x: 0, y: 0, width: 800, height: 500))
        surface.wantsLayer = true
        let mask = CAShapeLayer()
        surface.layer?.mask = mask
        panel.contentView = surface
        panel.shown = true
        let compact = CGRect(x: 300, y: 468, width: 200, height: 32)
        mask.path = CGPath(rect: compact, transform: nil)
        assert(panel.launcherPlacementFrame == compact.offsetBy(dx: 200, dy: 300))
        let grown = CGRect(x: 256, y: 432, width: 288, height: 68)
        mask.path = CGPath(rect: grown, transform: nil)
        assert(panel.launcherPlacementFrame == grown.offsetBy(dx: 200, dy: 300))
        panel.activeSpace = false
        assert(panel.launcherPlacementFrame == nil)
        panel.activeSpace = true
        panel.shown = false
        assert(panel.launcherPlacementFrame == nil)
        print("Passed: shown notch, grown message, external pill, hidden island, disabled preferences")
    }
}
