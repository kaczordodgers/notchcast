import CoreGraphics

struct MiddleClickFilter {
    enum ButtonEvent { case down, drag, up }
    enum Decision: Equatable { case pass, swallow, down, drag, up }
    private var held: Decision?

    mutating func decide(_ event: ButtonEvent, press: MiddleClickGuards.Press) -> Decision {
        switch event {
        case .down:
            held = press == .middle ? .down : press == .bounce ? .swallow : nil
            return held ?? .pass
        case .drag:
            return held == .down ? .drag : held ?? .pass
        case .up:
            defer { held = nil }
            return held == .down ? .up : held ?? .pass
        }
    }

    mutating func reset() -> Bool {
        defer { held = nil }
        return held == .down
    }

    // Rewriting the native event keeps the window and process WindowServer routed it to;
    // a new event posted after annotation has no target and reaches no app.
    static func rewrite(_ event: CGEvent, for decision: Decision) {
        switch decision {
        case .down: event.type = .otherMouseDown
        case .drag: event.type = .otherMouseDragged
        case .up: event.type = .otherMouseUp
        case .pass, .swallow: return
        }
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(CGMouseButton.center.rawValue))
    }
}
