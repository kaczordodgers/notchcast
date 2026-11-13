import Foundation

struct SoloistRefreshState {
    private(set) var deadline: TimeInterval?
    private var pending = false

    mutating func event(now: TimeInterval) -> [String] {
        if let deadline, now < deadline {
            pending = true
            return []
        }
        pending = false
        deadline = now + 0.4
        return [SoloistProtocol.getState]
    }

    mutating func flush(now: TimeInterval) -> [String] {
        guard let deadline, now >= deadline else { return [] }
        self.deadline = nil
        guard pending else { return [] }
        return event(now: now)
    }
}
