import Foundation

enum GreenMaximizeClick {
    struct PointerGate: Sendable {
        var zones: [CGRect] = []
        var zone: Int?

        mutating func moved(to point: CGPoint) -> Bool {
            let next = zones.firstIndex { $0.contains(point) }
            guard next != zone else { return false }
            zone = next
            return true
        }

        static func zone(bounds: CGRect, layer: Int) -> CGRect? {
            guard layer == 0, !bounds.isEmpty else { return nil }
            return bounds.intersection(CGRect(origin: bounds.origin, size: CGSize(width: 100, height: 40)))
        }
    }

    static func target<T>(pointer: T?, frontmost: T?, hit: (T) -> Bool) -> T? {
        if let pointer, hit(pointer) { return pointer }
        if let frontmost, hit(frontmost) { return frontmost }
        return nil
    }

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
