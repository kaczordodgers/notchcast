struct HideCommandMPolicy: Sendable {
    enum Decision: Equatable { case pass, swallow, hide }
    private var swallowing = false

    mutating func consume(keyDown: Bool, keyCode: Int64, plainCommand: Bool,
                          isRepeat: Bool, skipped: Bool) -> Decision {
        guard keyCode == 46 else { return .pass }
        guard keyDown else {
            defer { swallowing = false }
            return swallowing ? .swallow : .pass
        }
        if isRepeat { return swallowing ? .swallow : .pass }
        swallowing = plainCommand && !skipped
        return swallowing ? .hide : .pass
    }

    static func shouldHide(pid: Int32, ownPID: Int32, isFinder: Bool, hasWindows: Bool) -> Bool {
        pid > 0 && pid != ownPID && (!isFinder || hasWindows)
    }
}
