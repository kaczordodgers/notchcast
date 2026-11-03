// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/NotchcastLauncherGeometry.swift
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/NotchcastLauncherPlacement.swift
import AppKit

@MainActor
final class NotchcastPreferences {
    static let shared = NotchcastPreferences()
    var enabled: Set<NotchcastFeature> = [.island, .launcherFromIsland]
    func isOn(_ feature: NotchcastFeature) -> Bool { enabled.contains(feature) }
}

@main
@MainActor
struct NotchcastLauncherPlacementTests {
    static func main() {
        let frame = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
        let left = CGRect(x: -1920, y: 1248, width: 850, height: 32)
        let right = CGRect(x: -870, y: 1248, width: 870, height: 32)
        func anchor(_ top: CGFloat, left: CGRect? = nil, right: CGRect? = nil) -> CGPoint? {
            NotchcastLauncherGeometry.anchor(
                frame: frame, safeAreaTop: top, auxiliaryLeft: left, auxiliaryRight: right,
                width: 750, active: NotchcastLauncherPlacement.isActive)
        }
        assert(anchor(32, left: left, right: right) == CGPoint(x: -1345, y: 1240))
        assert(anchor(0) == CGPoint(x: -1335, y: 1244))
        assert(anchor(0, left: left, right: right)?.y == 1240)
        assert(anchor(0)?.x == frame.midX - 750 / 2)
        for feature in [NotchcastFeature.island, .launcherFromIsland] {
            NotchcastPreferences.shared.enabled.remove(feature)
            assert(!NotchcastLauncherPlacement.isActive)
            assert(anchor(32) == nil)
            NotchcastPreferences.shared.enabled.insert(feature)
            assert(anchor(32) == CGPoint(x: -1335, y: 1240))
        }
        print("Notched and monitor geometry, centring, and active/inactive nil contract passed")
    }
}
