import Foundation

enum GreenMaximizeClick {
    enum Event { case down, up, move, drag }

    struct Session: Sendable {
        var pressed = false

        mutating func decide(_ event: Event, hit: Bool) -> (swallow: Bool, maximize: Bool) {
            switch event {
            case .up:
                let owned = pressed
                pressed = false
                return (owned, false)
            case .drag: return (pressed, false)
            case .move: return (hit, false)
            case .down:
                pressed = hit
                return (hit, hit)
            }
        }
    }

    static func intercept(
        point: CGPoint, rect: CGRect?, age: TimeInterval, option: Bool,
        bundleID: String?, exclusions: Set<String>
    ) -> Bool {
        guard !option, age >= 0, age < 2, let rect, !rect.isEmpty,
            let bundleID, !exclusions.contains(bundleID)
        else { return false }
        return rect.contains(point)
    }
}
