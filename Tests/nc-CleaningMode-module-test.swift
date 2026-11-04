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

// notchcast-sources: Tinycast/Features/CleaningMode/CleaningModeModule.swift
@MainActor protocol NotchcastModule: AnyObject { func start(); func stop() }
@main struct ModuleTest {
    @MainActor static func main() {
        let fixture = Fixture()
        let module = CleaningModeModule(engine: fixture.engine, granted: { fixture.granted })
        module.begin()
        precondition(!fixture.engine.isActive)
        module.start()
        fixture.granted = false
        module.begin()
        precondition(module.needsGrant && !fixture.engine.isActive)
        fixture.granted = true
        module.begin()
        precondition(fixture.engine.isActive)
        module.stop()
        precondition(!fixture.engine.isActive && fixture.jobs.isEmpty && !module.needsGrant)
        module.begin()
        precondition(!fixture.engine.isActive)
        print("PASS start, stop, permission and switch off")
    }
}
