enum DictationIslandHUDPolicy {
    enum Phase: Sendable { case listening, transcribing }
    enum Presentation: Equatable, Sendable { case capsule, listening, transcribing }

    static func presentation(phase: Phase, enabled: Bool, islandAvailable: Bool) -> Presentation {
        guard enabled, islandAvailable else { return .capsule }
        return phase == .listening ? .listening : .transcribing
    }

    static func shouldShowProgress(presentation: Presentation, ownsMessage: Bool) -> Bool {
        presentation != .capsule && !ownsMessage
    }
}
