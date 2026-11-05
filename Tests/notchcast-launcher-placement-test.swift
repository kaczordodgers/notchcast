// notchcast-sources: Tinycast/Features/Notchcast/Launcher/NotchcastLauncherGeometry.swift
import CoreGraphics

@main
struct NotchcastLauncherPlacementTests {
    static func main() {
        // The palette's anchor is the grown frame's own top-left, so the two surfaces coincide.
        let underNotch = CGRect(x: -1345, y: 773, width: 750, height: 475)
        assert(NotchcastLauncherGeometry.anchor(launcherFrame: underNotch, width: 750) == CGPoint(x: -1345, y: 1248))
        let compact = CGRect(x: 2185, y: 1020, width: 750, height: 56)
        assert(NotchcastLauncherGeometry.anchor(launcherFrame: compact, width: 750) == CGPoint(x: 2185, y: 1076))
        assert(NotchcastLauncherGeometry.anchor(launcherFrame: nil, width: 750) == nil)
        print("Passed: grown frame anchor, compact anchor, no island")
    }
}
