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
    var closedBodyFrame = CGRect.zero
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
        panel.shown = true
        let compact = CGRect(x: 500, y: 768, width: 200, height: 32)
        panel.closedBodyFrame = compact
        assert(panel.launcherPlacementFrame == compact)
        let grown = CGRect(x: 456, y: 732, width: 288, height: 68)
        panel.closedBodyFrame = grown
        assert(panel.launcherPlacementFrame == grown, "the launcher hangs from the closed body, never its bubble")
        panel.activeSpace = false
        assert(panel.launcherPlacementFrame == nil)
        panel.activeSpace = true
        panel.shown = false
        assert(panel.launcherPlacementFrame == nil)
        print("Passed: shown notch, grown message, external pill, hidden island, disabled preferences")
    }
}
