import Foundation
import Synchronization

private final class CleaningModeState: Sendable {
    let policy = Mutex(CleaningModePolicy())
}

@MainActor
final class CleaningModeEngine {
    typealias Filter = @Sendable (CleaningModePolicy.Event) -> Bool
    typealias Schedule = (TimeInterval, Bool, @escaping @MainActor @Sendable () -> Void) -> () -> Void

    private let state = CleaningModeState()
    private let now: @Sendable () -> TimeInterval
    private let register: (@escaping Filter) -> UUID
    private let unregister: (UUID) -> Void
    private let facts: () -> (tapRunning: Bool, accessibilityGranted: Bool)
    private let schedule: Schedule
    private var registration: UUID?
    private var cancelTimeout: (() -> Void)?
    private var cancelPoll: (() -> Void)?

    var isActive: Bool { state.policy.withLock { $0.isActive } }
    var remaining: TimeInterval { state.policy.withLock { $0.remaining(now: now()) } }
    var unlockProgress: Int { state.policy.withLock { $0.unlock.progress } }

    init(
        now: @escaping @Sendable () -> TimeInterval,
        register: @escaping (@escaping Filter) -> UUID,
        unregister: @escaping (UUID) -> Void,
        facts: @escaping () -> (tapRunning: Bool, accessibilityGranted: Bool),
        schedule: @escaping Schedule
    ) {
        self.now = now
        self.register = register
        self.unregister = unregister
        self.facts = facts
        self.schedule = schedule
    }

    isolated deinit {
        cancelTimeout?()
        cancelPoll?()
        if let registration { unregister(registration) }
    }

    func start() {
        guard registration == nil, facts().accessibilityGranted else { return }
        state.policy.withLock { $0.start(now: now()) }
        registration = register { [state, now] event in
            state.policy.withLock { $0.swallow(event, now: now()) }
        }
        cancelTimeout = schedule(CleaningModePolicy.maximumDuration, false) { [weak self] in
            self?.stop()
        }
        cancelPoll = schedule(1, true) { [weak self] in self?.poll() }
    }

    func stop() {
        state.policy.withLock { $0.stop() }
        cancelTimeout?()
        cancelPoll?()
        cancelTimeout = nil
        cancelPoll = nil
        if let registration {
            self.registration = nil
            unregister(registration)
        }
    }

    func poll() {
        let health = facts()
        state.policy.withLock {
            $0.check(now: now(), tapRunning: health.tapRunning,
                     accessibilityGranted: health.accessibilityGranted)
        }
        if !isActive { stop() }
    }
}
