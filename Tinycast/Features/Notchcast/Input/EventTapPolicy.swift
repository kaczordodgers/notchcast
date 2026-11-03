import CoreGraphics
import Foundation

struct EventTapPolicy: Sendable {
    private(set) var consumers: [UUID: CGEventMask] = [:]

    var mask: CGEventMask { consumers.values.reduce(0, |) }
    var needsTap: Bool { mask != 0 }

    static func options(hasSynchronousConsumers: Bool) -> CGEventTapOptions {
        hasSynchronousConsumers ? .defaultTap : .listenOnly
    }

    mutating func register(_ id: UUID, mask: CGEventMask) {
        consumers[id] = mask
    }

    mutating func remove(_ id: UUID) {
        consumers.removeValue(forKey: id)
    }

    static func mask(for type: CGEventType) -> CGEventMask {
        guard type.rawValue < CGEventMask.bitWidth else { return 0 }
        return 1 << type.rawValue
    }

    static func shouldReenable(_ type: CGEventType, hasConsumers: Bool) -> Bool {
        hasConsumers && (type == .tapDisabledByTimeout || type == .tapDisabledByUserInput)
    }
}
