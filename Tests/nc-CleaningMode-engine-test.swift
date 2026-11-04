// notchcast-sources: Tinycast/Features/CleaningMode/Model/*.swift
// notchcast-sources: Tinycast/Features/CleaningMode/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Input/*.swift
import Foundation
import Synchronization

enum Paster {
    static let tinycastEventTag: Int64 = 0
}

@MainActor
private final class Fixture {
    var filter: CleaningModeEngine.Filter?
    var running = true
    var granted = true
    var removals = 0
    var jobs: [UUID: (TimeInterval, TimeInterval?, @MainActor @Sendable () -> Void)] = [:]

    lazy var engine = CleaningModeEngine(
        now: { [clock = self.clockBox] in clock.value.withLock { $0 } },
        register: { [unowned self] filter in self.filter = filter; return UUID() },
        unregister: { [unowned self] _ in self.removals += 1; self.filter = nil },
        facts: { [unowned self] in (self.running, self.granted) },
        schedule: { [unowned self] interval, repeats, action in
            let id = UUID()
            self.jobs[id] = (self.time + interval, repeats ? interval : nil, action)
            return { [weak self] in self?.jobs.removeValue(forKey: id) }
        }
    )
    let clockBox = TestClock()
    var time: TimeInterval { clockBox.value.withLock { $0 } }

    func advance(to target: TimeInterval) {
        while let next = jobs.min(by: { $0.value.0 < $1.value.0 }), next.value.0 <= target {
            clockBox.value.withLock { $0 = next.value.0 }
            if let interval = next.value.1 {
                jobs[next.key]?.0 += interval
            } else {
                jobs.removeValue(forKey: next.key)
            }
            next.value.2()
        }
        clockBox.value.withLock { $0 = target }
    }

    func send(_ event: CleaningModePolicy.Event) -> Bool { filter?(event) ?? false }
}

private final class TestClock: Sendable {
    let value = Mutex<TimeInterval>(0)
}

@main
struct CleaningModeEngineTests {
    @MainActor
    static func main() {
        let fixture = Fixture()
        precondition(!fixture.engine.isActive && fixture.filter == nil)
        fixture.engine.start()
        for _ in 0..<4 { precondition(fixture.send(.keyDown(code: 53, isRepeat: false))) }
        precondition(fixture.engine.unlockProgress == 4)
        precondition(fixture.send(.keyDown(code: 53, isRepeat: true)))
        precondition(fixture.engine.unlockProgress == 4)
        precondition(fixture.send(.keyDown(code: 0, isRepeat: false)))
        precondition(fixture.engine.unlockProgress == 0)
        for _ in 0..<4 { precondition(fixture.send(.keyDown(code: 53, isRepeat: false))) }
        precondition(fixture.send(.systemKey))
        precondition(fixture.engine.unlockProgress == 0)
        precondition(fixture.send(.modifier))
        precondition(fixture.send(.keyUp))
        precondition(!fixture.send(.other))
        for _ in 0..<5 { precondition(fixture.send(.keyDown(code: 53, isRepeat: false))) }
        precondition(!fixture.engine.isActive)
        fixture.advance(to: 1)
        precondition(fixture.removals == 1 && fixture.jobs.isEmpty)
        fixture.engine.stop()
        fixture.engine.stop()
        precondition(fixture.removals == 1)
        print("PASS gesture, repeats, stray reset, media/brightness swallowing, idempotent stop")

        let timeout = Fixture()
        timeout.engine.start()
        timeout.jobs = timeout.jobs.filter { $0.value.1 == nil }
        timeout.advance(to: 299.999)
        precondition(timeout.engine.isActive)
        timeout.advance(to: 300)
        precondition(!timeout.engine.isActive && timeout.removals == 1 && timeout.jobs.isEmpty)
        print("PASS independent timeout at exactly 300 seconds with zero events")

        for grantLoss in [false, true] {
            let health = Fixture()
            health.engine.start()
            if grantLoss { health.granted = false } else { health.running = false }
            health.advance(to: 1)
            precondition(!health.engine.isActive && health.removals == 1 && health.jobs.isEmpty)
        }
        print("PASS poll unregisters on grant loss and stopped hub")

        var counter = CleaningUnlockCounter()
        precondition(!counter.registerKeyDown(code: 53, time: 0, isRepeat: false))
        precondition(!counter.registerKeyDown(code: 53, time: 6, isRepeat: false))
        precondition(counter.progress == 2)
        precondition(!counter.registerKeyDown(code: 53, time: 12.001, isRepeat: false))
        precondition(counter.progress == 1)
        print("PASS injected clock press window")

        var policy = CleaningModePolicy()
        policy.start(now: 10)
        precondition(policy.swallow(.systemKey, now: 309.999))
        precondition(!policy.swallow(.systemKey, now: 310))
        precondition(!policy.isActive)
        let denied = Fixture()
        denied.granted = false
        denied.engine.start()
        precondition(!denied.engine.isActive && denied.filter == nil && denied.jobs.isEmpty)
        print("PASS event deadline bound and denied start")
    }
}
