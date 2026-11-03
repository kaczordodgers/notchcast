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
        let upstream = CGPoint(x: 100, y: 600)
        let frame = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
        let left = CGRect(x: -1920, y: 1248, width: 850, height: 32)
        let right = CGRect(x: -870, y: 1248, width: 870, height: 32)
        func anchor(_ top: CGFloat, left: CGRect? = nil, right: CGRect? = nil) -> CGPoint {
            NotchcastLauncherGeometry.anchor(
                frame: frame, safeAreaTop: top, auxiliaryLeft: left, auxiliaryRight: right,
                width: 750, active: NotchcastLauncherPlacement.isActive, default: upstream)
        }
        assert(anchor(32, left: left, right: right) == CGPoint(x: -1345, y: 1240))
        assert(anchor(0) == CGPoint(x: -1335, y: 1244))
        assert(anchor(0, left: left, right: right).y == 1240)
        let storedOffset = CGPoint(x: 50, y: 100)
        func resolved() -> CGPoint {
            if !NotchcastLauncherPlacement.isActive {
                return CGPoint(x: frame.minX + storedOffset.x, y: frame.maxY - storedOffset.y)
            }
            return anchor(32)
        }
        assert(resolved() == anchor(32))
        for feature in [NotchcastFeature.island, .launcherFromIsland] {
            NotchcastPreferences.shared.enabled.remove(feature)
            assert(!NotchcastLauncherPlacement.isActive)
            assert(anchor(32) == upstream)
            assert(resolved() == CGPoint(x: -1870, y: 1180))
            NotchcastPreferences.shared.enabled.insert(feature)
            assert(resolved() == anchor(32))
        }
        assert(storedOffset == CGPoint(x: 50, y: 100))
        print("Notched and monitor anchors, both switches, and retained offsets passed")
    }
}
