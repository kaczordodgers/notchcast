import Foundation

struct CleaningModePolicy: Sendable {
    enum Event: Sendable {
        case keyDown(code: Int64, isRepeat: Bool)
        case keyUp
        case modifier
        case systemKey
        case other
    }

    private(set) var isActive = false
    private(set) var unlock = CleaningUnlockCounter()
    private var deadline: TimeInterval = 0
    static let maximumDuration: TimeInterval = 300
    func remaining(now: TimeInterval) -> TimeInterval { isActive ? max(0, deadline - now) : 0 }

    mutating func start(now: TimeInterval) {
        guard !isActive else { return }
        unlock.reset()
        deadline = now + Self.maximumDuration
        isActive = true
    }

    mutating func stop() {
        isActive = false
        unlock.reset()
    }

    mutating func check(now: TimeInterval, tapRunning: Bool, accessibilityGranted: Bool) {
        if now >= deadline || !tapRunning || !accessibilityGranted { stop() }
    }

    mutating func swallow(_ event: Event, now: TimeInterval) -> Bool {
        if now >= deadline { stop() }
        guard isActive else { return false }
        switch event {
        case .keyDown(let code, let isRepeat):
            if unlock.registerKeyDown(code: code, time: now, isRepeat: isRepeat) { stop() }
        case .modifier, .systemKey:
            unlock.reset()
        case .keyUp:
            break
        case .other:
            return false
        }
        return true
    }
}
