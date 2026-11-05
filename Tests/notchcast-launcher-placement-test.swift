// notchcast-sources: Tinycast/Features/Notchcast/Launcher/NotchcastLauncherGeometry.swift
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/IslandPanel+LauncherPlacement.swift
import AppKit
import QuartzCore

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
        // The palette's anchor is the grown frame's own top-left, so the two surfaces coincide.
        let underNotch = CGRect(x: -1345, y: 773, width: 750, height: 475)
        assert(NotchcastLauncherGeometry.anchor(launcherFrame: underNotch, width: 750) == CGPoint(x: -1345, y: 1248))
        let compact = CGRect(x: 2185, y: 1020, width: 750, height: 56)
        assert(NotchcastLauncherGeometry.anchor(launcherFrame: compact, width: 750) == CGPoint(x: 2185, y: 1076))
        assert(NotchcastLauncherGeometry.anchor(launcherFrame: nil, width: 750) == nil)
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
        let closed = CGRect(x: 300, y: 468, width: 200, height: 32)
        mask.path = CGPath(rect: closed, transform: nil)
        assert(panel.launcherPlacementFrame == closed.offsetBy(dx: 200, dy: 300))
        let grown = CGRect(x: 256, y: 432, width: 288, height: 68)
        mask.path = CGPath(rect: grown, transform: nil)
        assert(panel.launcherPlacementFrame == grown.offsetBy(dx: 200, dy: 300))
        panel.activeSpace = false
        assert(panel.launcherPlacementFrame == nil)
        panel.activeSpace = true
        panel.shown = false
        assert(panel.launcherPlacementFrame == nil)
        print("Passed: grown frame anchor, compact anchor, no island, hidden island")
    }
}
