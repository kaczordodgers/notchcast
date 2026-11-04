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
}
