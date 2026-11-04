struct VoiceAskHold: Sendable {
    enum State: Sendable { case idle, pending, recording, combo }
    enum Action { case none, begin, finish, cancel }
    private(set) var state: State = .idle

    mutating func press(alone: Bool) {
        guard state == .idle else { return }
        state = alone ? .pending : .combo
    }

    mutating func threshold() -> Action {
        guard state == .pending else { return .none }
        state = .recording
        return .begin
    }

    mutating func chord() -> Action {
        guard state != .idle else { return .none }
        let action: Action = state == .recording ? .cancel : .none
        state = .combo
        return action
    }

    mutating func release() -> Action {
        defer { state = .idle }
        return state == .recording ? .finish : .none
    }

    mutating func reset() { state = .idle }
}
