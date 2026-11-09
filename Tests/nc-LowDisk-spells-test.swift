import AppKit
import Foundation

@main
struct LowDiskTests {
    @MainActor final class Reader {
        var value = LowDiskEngine.Space(free: 29_000_000_000, total: 200_000_000_000)
        var calls = 0
        var suspended = false
        var continuation: CheckedContinuation<LowDiskEngine.Space, Never>?

        func read() async -> LowDiskEngine.Space {
            calls += 1
            if suspended { return await withCheckedContinuation { continuation = $0 } }
            return value
        }
    }

    @MainActor static func main() async {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            checks += 1
            if !condition { fatalError(message) }
        }
        let billion: Int64 = 1_000_000_000
        var engine = LowDiskEngine()
        check(!engine.consume(.init(free: 30 * billion, total: 300 * billion)), "Exact warning thresholds are healthy")
        check(engine.consume(.init(free: 29 * billion, total: 100 * billion)), "Absolute free bytes warn")
        check(!engine.consume(.init(free: 40 * billion, total: 100 * billion)) && engine.isLow, "Bytes hysteresis")
        check(!engine.consume(.init(free: 45 * billion, total: 400 * billion)) && engine.isLow, "Fraction must also recover")
        check(!engine.consume(.init(free: 45 * billion, total: 300 * billion)) && !engine.isLow, "Both clear boundaries")
        check(engine.consume(.init(free: 99 * billion, total: 1000 * billion)), "Percentage alone warns")
        check(!engine.consume(.init(free: 149 * billion, total: 1000 * billion)) && engine.isLow, "Percentage hysteresis")
        check(!engine.consume(.init(free: 150 * billion, total: 1000 * billion)) && !engine.isLow, "15% clears")
        check(!engine.consume(.init(free: -1, total: 100)) && !engine.isLow, "Negative capacity ignored")
        check(!engine.consume(.init(free: 1, total: 0)) && !engine.isLow, "Zero total ignored")
        check(!engine.consume(.init(free: 101, total: 100)) && !engine.isLow, "Impossible capacity ignored")

        let suite = "nc.disk.tests.\(UUID())"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Test defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let reader = Reader()
        let center = NotificationCenter()
        var notices = 0
        let manager = LowDiskManager(defaults: defaults, wakeCenter: center, read: { await reader.read() })
        manager.onNotice = { _ in notices += 1 }
        manager.start()
        manager.start()
        await manager.settled()
        check(notices == 1 && manager.engine.isLow && reader.calls == 1, "One startup check and one notice")
        manager.refresh()
        await manager.settled()
        check(notices == 1, "Repeated low reads stay quiet")
        manager.stop()
        let restarted = LowDiskManager(defaults: defaults, wakeCenter: center, read: { await reader.read() })
        restarted.onNotice = { _ in notices += 1 }
        restarted.start()
        await restarted.settled()
        check(notices == 1 && restarted.engine.isLow, "Low spell survives service restart")
        reader.value = .init(free: 50 * billion, total: 200 * billion)
        center.post(NSWorkspace.DidWakeMessage())
        await restarted.settled()
        check(!restarted.engine.isLow, "Wake checks and clears the spell")
        reader.value = .init(free: 20 * billion, total: 200 * billion)
        restarted.refresh()
        await restarted.settled()
        check(notices == 2, "Recovered disk begins a new spell")
        reader.suspended = true
        restarted.refresh()
        while reader.continuation == nil { await Task.yield() }
        restarted.refresh()
        restarted.refresh()
        reader.suspended = false
        reader.continuation?.resume(returning: .init(free: 50 * billion, total: 200 * billion))
        reader.continuation = nil
        await restarted.settled()
        check(reader.calls == 7, "Multiple refreshes coalesce to one follow-up")
        check(restarted.engine.isLow && notices == 3, "Follow-up sees the current disk")
        reader.suspended = true
        restarted.refresh()
        while reader.continuation == nil { await Task.yield() }
        restarted.stop()
        reader.continuation?.resume(returning: .init(free: 100 * billion, total: 200 * billion))
        reader.continuation = nil
        await Task.yield()
        check(restarted.engine.isLow, "Stopped read cannot mutate the spell")
        print("PASS: \(checks) disk threshold, persistence, wake and stale-result checks")
    }
}
