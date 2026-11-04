import Foundation

struct DictationTriggerEngine: Sendable {
    enum Input: Sendable {
        case down(isRecording: Bool)
        case up
        case confirm
        case otherInput
        case finish
        case reset
    }

    enum Action: Equatable, Sendable { case start, finish, cancel }

    static let holdThreshold: TimeInterval = 0.35

    private struct Press: Sendable {
        let startedAt: TimeInterval
        let wasRecording: Bool
    }

    private var press: Press?
    private var ownsRecording = false

    mutating func handle(_ input: Input, at now: TimeInterval) -> Action? {
        switch input {
        case .down(let isRecording):
            guard press == nil else { return nil }
            if !isRecording { ownsRecording = false }
            press = Press(startedAt: now, wasRecording: isRecording)
            return nil
        case .confirm:
            guard let press, !press.wasRecording, !ownsRecording,
                  now >= press.startedAt + Self.holdThreshold else { return nil }
            ownsRecording = true
            return .start
        case .up:
            guard let press else { return nil }
            self.press = nil
            if press.wasRecording || ownsRecording {
                ownsRecording = false
                return .finish
            }
            ownsRecording = true
            return .start
        case .otherInput:
            guard let press else { return nil }
            self.press = nil
            guard !press.wasRecording, ownsRecording else { return nil }
            ownsRecording = false
            return now >= press.startedAt + Self.holdThreshold ? .finish : .cancel
        case .finish:
            press = nil
            ownsRecording = false
            return .finish
        case .reset:
            press = nil
            guard ownsRecording else { return nil }
            ownsRecording = false
            return .finish
        }
    }
}
