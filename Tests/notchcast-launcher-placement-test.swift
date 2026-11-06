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
final class NotchcastLauncherSurface {
    static let shared = NotchcastLauncherSurface()
    static var preferredScreen: NSScreen? { nil }
    func prepare(attached: Bool) {}
}

@MainActor
final class IslandPanel: NSPanel {
    var displayFrame: CGRect { frame }
    var hardwareNotch: CGRect?
    var shown = false
    var activeSpace = true
    var closedBodyFrame = CGRect.zero
    var openBodyFrame = CGRect.zero
    override var isVisible: Bool { shown }
    override var isOnActiveSpace: Bool { activeSpace }
}

@main
@MainActor
struct NotchcastLauncherPlacementTests {
    static func main() {
        let panel = IslandPanel(contentRect: .zero, styleMask: .borderless,
                                backing: .buffered, defer: false)
        func anchor() -> CGPoint? {
            NotchcastLauncherGeometry.anchor(
                attachment: panel.launcherAttachment, width: 750, active: NotchcastLauncherPlacement.isActive)
        }
        assert(anchor() == nil, "a hidden island hangs nothing")
        panel.shown = true
        panel.hardwareNotch = CGRect(x: -1070, y: 1248, width: 200, height: 32)
        panel.closedBodyFrame = CGRect(x: -1070, y: 1248, width: 200, height: 32)
        assert(anchor() == CGPoint(x: -1345, y: 1248), "the launcher's top sits under the notch, part of the black")
        panel.closedBodyFrame = CGRect(x: -1114, y: 1212, width: 288, height: 68)
        assert(anchor() == CGPoint(x: -1345, y: 1248), "a grown message leaves the launcher under the notch")
        panel.hardwareNotch = nil
        panel.closedBodyFrame = CGRect(x: 2470, y: 1045, width: 180, height: 31)
        assert(anchor() == CGPoint(x: 2185, y: 1076), "on a monitor the launcher's top is level with the pill's")
        for feature in [NotchcastFeature.island, .launcherFromIsland] {
            NotchcastPreferences.shared.enabled.remove(feature)
            assert(anchor() == nil)
            NotchcastPreferences.shared.enabled.insert(feature)
            assert(anchor() != nil)
        }
        panel.activeSpace = false
        assert(panel.launcherAttachment == nil)
        panel.activeSpace = true
        panel.shown = false
        assert(panel.launcherAttachment == nil)
        hostingIsland()
        print("Passed: notch, grown message, monitor pill, hidden island, disabled preferences, hosting island")
    }

    /// Only the island the launcher was hung from grows into it.
    static func hostingIsland() {
        func island(_ display: CGRect) -> IslandPanel {
            let panel = IslandPanel(contentRect: display, styleMask: .borderless, backing: .buffered, defer: false)
            panel.setFrame(display, display: false)
            panel.shown = true
            panel.closedBodyFrame = CGRect(x: display.midX - 100, y: display.maxY - 32, width: 200, height: 32)
            return panel
        }
        let builtIn = island(CGRect(x: 0, y: 0, width: 1512, height: 982))
        let external = island(CGRect(x: 1512, y: 0, width: 2560, height: 1440))
        let panels = [builtIn, external]
        let underBuiltIn = CGRect(x: 381, y: 467, width: 750, height: 475)
        let underExternal = CGRect(x: 2417, y: 925, width: 750, height: 475)
        assert(NotchcastLauncherPlacement.island(hosting: underBuiltIn, among: panels) === builtIn)
        assert(NotchcastLauncherPlacement.island(hosting: underExternal, among: panels) === external)
        external.activeSpace = false
        assert(NotchcastLauncherPlacement.island(hosting: underExternal, among: panels) == nil,
               "a full-screen space without the island: the launcher sits at its own spot and nothing grows")
        external.activeSpace = true
        external.shown = false
        assert(NotchcastLauncherPlacement.island(hosting: underExternal, among: panels) == nil)
        external.shown = true
        NotchcastPreferences.shared.enabled.remove(.launcherFromIsland)
        assert(NotchcastLauncherPlacement.island(hosting: underBuiltIn, among: panels) == nil)
        NotchcastPreferences.shared.enabled.insert(.launcherFromIsland)
        let offscreen = CGRect(x: -3000, y: 0, width: 750, height: 475)
        assert(NotchcastLauncherPlacement.island(hosting: offscreen, among: panels) == nil)
        openIslandGivesWay(builtIn, external, underBuiltIn)
    }

    /// An open island closes for a launcher hung from it or one it covers or touches, and stays open otherwise.
    static func openIslandGivesWay(_ builtIn: IslandPanel, _ external: IslandPanel, _ launcher: CGRect) {
        builtIn.openBodyFrame = CGRect(x: 356, y: 662, width: 800, height: 320)
        assert(NotchcastLauncherPlacement.displaces(builtIn, launcher: launcher, host: builtIn))
        assert(NotchcastLauncherPlacement.displaces(builtIn, launcher: launcher, host: nil),
               "placement off, but the open island would still sit over the launcher")
        let touching = CGRect(x: 381, y: 187, width: 750, height: 475)
        assert(NotchcastLauncherPlacement.displaces(builtIn, launcher: touching, host: nil),
               "a launcher meeting the open island's edge still gives way")
        let below = CGRect(x: 381, y: 100, width: 750, height: 475)
        assert(!NotchcastLauncherPlacement.displaces(builtIn, launcher: below, host: nil),
               "placement off and apart: a pinned island stays open")
        assert(!NotchcastLauncherPlacement.displaces(builtIn, launcher: below, host: external),
               "a launcher hung from another display's island leaves this one open")
    }
}
