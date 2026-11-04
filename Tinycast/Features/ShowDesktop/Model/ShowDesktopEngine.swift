struct ShowDesktopEngine: Sendable {
    enum Decision: Equatable, Sendable {
        case pass, swallow, toggle
    }

    private var swallowing = false

    mutating func decide(isKeyDown: Bool, keyCode: Int64, hasModifiers: Bool,
                         isRepeat: Bool) -> Decision {
        guard keyCode == 160 else { return .pass }
        guard isKeyDown else {
            defer { swallowing = false }
            return swallowing ? .swallow : .pass
        }
        if isRepeat { return swallowing ? .swallow : .pass }
        guard !hasModifiers else {
            swallowing = false
            return .pass
        }
        swallowing = true
        return .toggle
    }
}
