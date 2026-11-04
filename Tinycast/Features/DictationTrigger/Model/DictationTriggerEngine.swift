import Foundation

struct DictationTriggerEngine: Sendable {
    enum Input: Sendable {
        case down(isRecording: Bool)
        case up
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

    mutating func handle(_ input: Input, at now: TimeInterval) -> Action? {
        switch input {
        case .down(let isRecording):
            guard press == nil else { return nil }
            press = Press(startedAt: now, wasRecording: isRecording)
            return isRecording ? nil : .start
        case .up:
            guard let press else { return nil }
            self.press = nil
            return press.wasRecording || now - press.startedAt >= Self.holdThreshold ? .finish : nil
        case .otherInput:
            guard let press else { return nil }
            self.press = nil
            return press.wasRecording ? nil : .cancel
        case .finish:
            press = nil
            return .finish
        case .reset:
            guard let press else { return nil }
            self.press = nil
            return press.wasRecording ? nil : .finish
        }
    }
}
