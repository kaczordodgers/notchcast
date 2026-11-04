struct VoiceAskResult: Sendable, Equatable {
    enum RunState: Sendable { case running, completed, failed }
    let state: RunState
    let firstLines: [String]
}
