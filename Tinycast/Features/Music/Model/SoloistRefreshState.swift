import Foundation

struct SoloistRefreshState {
    private(set) var deadline: TimeInterval?
    private var pending = false
    private var pendingQueue = false

    mutating func event(queue: Bool, now: TimeInterval) -> [String] {
        if let deadline, now < deadline {
            pending = true
            pendingQueue = pendingQueue || queue
            return []
        }
        let needsQueue = queue || pendingQueue
        pending = false
        pendingQueue = false
        deadline = now + 0.4
        return [SoloistProtocol.getState] + (needsQueue ? [SoloistProtocol.getQueue] : [])
    }

    mutating func flush(now: TimeInterval) -> [String] {
        guard let deadline, now >= deadline else { return [] }
        self.deadline = nil
        guard pending else { return [] }
        return event(queue: pendingQueue, now: now)
    }
}
