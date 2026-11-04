// notchcast-sources: Tinycast/Features/AudioPriority/Model/*.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityPreferences.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityStore.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Model/*.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Service/*.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Store/MonitorStore.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Store/FanControl.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Store/MonitorModule.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Store/MonitorAlerts.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Store/MonitorAlertPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Root/RootContract.swift
// notchcast-sources: Tinycast/Features/Notchcast/Root/RootHelperClient.swift
// notchcast-sources: Tinycast/Features/Notchcast/Root/RootWait.swift
// notchcast-sources: Tinycast/Features/Notchcast/Root/RootToolPath.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift
import Foundation

@MainActor
final class FakeFans {
    var calls: [RootContract.Command] = []
    var active = 0
    var maximumActive = 0
    var failure: RootHelperClient.Failure?
    var gate: CheckedContinuation<Void, Never>?

    func run(_ command: RootContract.Command) async throws {
        active += 1
        maximumActive = max(maximumActive, active)
        calls.append(command)
        defer { active -= 1 }
        if command == .fansMedium {
            await withCheckedContinuation { gate = $0 }
            if let failure { throw failure }
        }
    }
}

@MainActor
final class SampleProbe {
    var count = 0
    func sample() -> MonitorSnapshot {
        count += 1
        return MonitorSnapshot(cpu: CPUReading(
            usage: .init(totalPercent: 25, userPercent: 10, systemPercent: 15),
            cores: [], loadAverage: nil))
    }
}

@main
@MainActor
struct MonitorStoreTests {
    static func settle() async {
        for _ in 0..<200 { await Task.yield() }
    }

    static func main() async {
        let probe = SampleProbe()
        let store = MonitorStore(sample: { await probe.sample() })
        store.start()
        await settle()
        precondition(probe.count == 0 && store.demand == 0)
        store.acquire()
        for _ in 0..<1000 where store.histories["cpu"] == nil { await Task.yield() }
        precondition(store.histories["cpu"]?.latest == 25)
        store.acquire()
        precondition(store.demand == 2)
        store.release()
        precondition(store.demand == 1)
        store.release()
        store.release()
        precondition(store.demand == 0)
        await settle()
        let count = probe.count
        await settle()
        precondition(probe.count == count)
        store.stop()

        let suite = "monitor-module-test.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        preferences.set(.systemMonitor, true)
        preferences.set(.monitorAlerts, false)
        let module = MonitorModule(preferences: preferences, store: store, alertSink: { _ in })
        let initialCount = probe.count
        module.start()
        await settle()
        precondition(store.demand == 0 && probe.count == initialCount)
        for _ in 0..<3 {
            preferences.set(.monitorAlerts, true)
            await settle()
            module.start()
            precondition(store.demand == 1)
            preferences.set(.monitorAlerts, false)
            await settle()
            precondition(store.demand == 0)
        }
        preferences.set(.monitorAlerts, true)
        await settle()
        module.stop()
        module.stop()
        precondition(store.demand == 0)
        module.start()
        await settle()
        precondition(store.demand == 1)
        preferences.set(.systemMonitor, false)
        await settle()
        precondition(store.demand == 0)
        module.stop()
        preferences.set(.monitorAlerts, false)
        await settle()
        precondition(store.demand == 0)

        for failure in [RootHelperClient.Failure.timedOut, .launchFailed, .executionFailed(2)] {
            let fake = FakeFans()
            fake.failure = failure
            let fans = FanControl(runner: { try await fake.run($0) })
            fans.set(.medium)
            await settle()
            precondition(fake.calls == [.fansMedium])
            fans.set(.max)
            fans.restore()
            fans.set(.max)
            fake.gate?.resume()
            await fans.waitUntilIdle()
            precondition(fake.maximumActive == 1)
            precondition(fake.calls == [.fansMedium, .fansAuto, .fansMax])
            fans.restore()
            await fans.waitUntilIdle()
            precondition(fake.calls.last == .fansAuto)
        }
        let cancelled = FanControl(runner: { command in
            if command != .fansAuto { throw CancellationError() }
        })
        cancelled.set(.medium)
        await cancelled.waitUntilIdle()
        precondition(cancelled.mode == .auto)
        let restored = FakeFans()
        var persisted = FanControl.Mode.auto
        var failures = 0
        var attempts = 0
        let retrying = FanControl(confirmed: { persisted = $0 }, failed: { failures += 1 }, runner: { command in
            if command == .fansMax { throw RootHelperClient.Failure.launchFailed }
        })
        for _ in 0..<2 {
            retrying.set(.max)
            await retrying.waitUntilIdle()
            attempts += 1
            precondition(persisted == .auto && retrying.mode == .auto && failures == attempts)
        }
        let recovery = FakeFans()
        var journalData: Data?
        let seed = FanControl(persist: { journalData = $0 }, runner: { _ in })
        seed.set(.max)
        await seed.waitUntilIdle()
        persisted = .max
        let crashed = FanControl(confirmed: { persisted = $0 }, journalData: journalData,
                                 runner: { try await recovery.run($0) })
        crashed.restore(preservingPreference: true)
        await crashed.waitUntilIdle()
        crashed.restore()
        await crashed.waitUntilIdle()
        precondition(recovery.calls == [.fansAuto] && persisted == .max)
        let fans = FanControl(runner: { try await restored.run($0) })
        fans.restore()
        await fans.waitUntilIdle()
        precondition(restored.calls.isEmpty)
        fans.set(.max)
        await fans.waitUntilIdle()
        fans.restore()
        fans.restore()
        await fans.waitUntilIdle()
        precondition(restored.calls == [.fansMax, .fansAuto])
        var saved = FanControl.Mode.max
        let shutdown = FanControl(confirmed: { saved = $0 }, journalData: journalData, runner: { _ in })
        shutdown.restore(preservingPreference: true)
        await shutdown.waitUntilIdle()
        precondition(saved == .max && shutdown.mode == .auto)
        var recoveryFailures = 0
        let missing = FanControl(confirmed: { saved = $0 }, failed: { recoveryFailures += 1 },
                                 journalData: journalData,
                                 runner: { _ in throw RootHelperClient.Failure.launchFailed })
        missing.restore(silently: true)
        await missing.waitUntilIdle()
        precondition(saved == .max && recoveryFailures == 0 && missing.failure != nil)
        print("PASS: demand counts, serialized latest request, restore after timeout/failure/cancellation and shutdown")
    }
}
