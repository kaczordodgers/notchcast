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
// notchcast-sources: Tinycast/Features/SystemMonitor/MonitorModule+Registration.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastHost.swift
// notchcast-kit: core root platform
// notchcast-sources: Tinycast/Features/Notchcast/Root/RootHelperClient.swift
// notchcast-sources: Tinycast/Features/Notchcast/Root/RootWait.swift
// notchcast-sources: Tinycast/Features/Notchcast/Root/RootToolPath.swift
import Foundation

enum DialogTone { case danger }

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
    var pending: CheckedContinuation<MonitorSnapshot, Never>?
    let percent: Double
    init(percent: Double = 25) { self.percent = percent }
    func gatedSample() async -> MonitorSnapshot {
        await withCheckedContinuation { pending = $0 }
    }
    func sample() -> MonitorSnapshot {
        count += 1
        return MonitorSnapshot(cpu: CPUReading(
            usage: .init(totalPercent: percent, userPercent: percent, systemPercent: 0),
            cores: [], loadAverage: nil))
    }
}

/// The store's nap, owned by the harness: it ends on `end()` or when the store cancels it.
@MainActor
final class Naps {
    private var parked = 0
    private var ended = 0
    var isParked: Bool { parked > ended }

    func nap() async throws {
        parked += 1
        let ticket = parked
        defer { ended = max(ended, ticket) }
        while ended < ticket {
            try Task.checkCancellation()
            await Task.yield()
        }
    }

    func end() async {
        await MonitorStoreTests.until("store naps after its sample") { isParked }
        ended = parked
    }
}

@main
@MainActor
struct MonitorStoreTests {
    static func settle() async {
        for _ in 0..<200 { await Task.yield() }
    }

    static func until(_ message: String, _ done: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(30)
        while !done() {
            guard ContinuousClock.now < deadline else { fatalError("Timed out: \(message)") }
            await Task.yield()
        }
    }

    static func main() async {
        let registered = MonitorModule.register()
        precondition(registered.count == 1 && registered[0].module === MonitorModule.shared)
        precondition(registered[0].requires == [.systemMonitor] && registered[0].requiresAny.isEmpty)
        print("PASS: the monitor registers its one module behind the System Monitor switch")

        let wakeProbe = SampleProbe()
        let wakeAlerts = SampleProbe(percent: 95)
        let wakeNaps = Naps()
        let waking = MonitorStore(sample: { await wakeProbe.sample() },
                                  alertSample: { await wakeAlerts.sample() },
                                  sleep: { _ in try await wakeNaps.nap() })
        waking.start()
        let wakeBackground = waking.beginDemand(alertsOnly: true)
        await until("alerts-only sample parks before the page opens") {
            waking.latest.cpu?.usage?.totalPercent == 95 && wakeNaps.isParked
        }
        precondition(waking.latest.cpu?.usage?.totalPercent == 95)
        let wakePage = waking.beginDemand()
        precondition(waking.latest.cpu?.usage?.totalPercent != 95)
        await until("page wakes full sampler without advancing its clock") {
            wakeProbe.count > 0 && waking.latest.cpu?.usage?.totalPercent == 25
        }
        precondition(waking.latest.cpu?.usage?.totalPercent == 25)
        wakePage.cancel()
        wakeBackground.cancel()
        waking.stop()

        let gated = SampleProbe()
        let raceNaps = Naps()
        let racing = MonitorStore(sample: { await wakeProbe.sample() }, alertSample: {
            await gated.gatedSample()
        }, sleep: { _ in try await raceNaps.nap() })
        racing.start()
        let raceBackground = racing.beginDemand(alertsOnly: true)
        await until("alerts-only sample is in flight") { gated.pending != nil }
        let racePage = racing.beginDemand()
        gated.pending?.resume(returning: wakeAlerts.sample())
        await until("full sampler replaces the in-flight alerts reading") {
            precondition(racing.latest.cpu?.usage?.totalPercent != 95,
                         "in-flight alerts reading must never reach visible page")
            return racing.latest.cpu?.usage?.totalPercent == 25
        }
        precondition(racing.latest.cpu?.usage?.totalPercent == 25)
        racePage.cancel()
        raceBackground.cancel()
        racing.stop()
        print("PASS: page wakes without advancing its clock and rejects in-flight alerts-only readings")

        let naps = Naps()
        let probe = SampleProbe()
        let alertProbe = SampleProbe(percent: 95)
        let store = MonitorStore(sample: { await probe.sample() },
                                 alertSample: { await alertProbe.sample() },
                                 sleep: { _ in try await naps.nap() })
        store.start()
        await settle()
        precondition(probe.count == 0 && store.demand == 0)
        let firstDemand = store.beginDemand()
        for _ in 0..<1000 where store.histories["cpu"] == nil { await Task.yield() }
        precondition(store.histories["cpu"]?.latest == 25)
        let secondDemand = store.beginDemand()
        precondition(store.demand == 2)
        firstDemand.cancel()
        precondition(store.demand == 1)
        secondDemand.cancel()
        secondDemand.cancel()
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
        let history = store.histories["cpu"]?.values
        module.start()
        await settle()
        precondition(store.demand == 0 && probe.count == initialCount)
        for _ in 0..<3 {
            preferences.set(.monitorAlerts, true)
            await settle()
            module.start()
            precondition(store.demand == 1)
            precondition(probe.count == initialCount, "alerts-only demand must not invoke full sampler")
            preferences.set(.monitorAlerts, false)
            await settle()
            precondition(store.demand == 0)
        }
        preferences.set(.monitorAlerts, true)
        await settle()
        precondition(alertProbe.count > 0, "alerts-only probe must run")
        precondition(store.latest.cpu?.usage?.totalPercent == 95, "alert values reach latest")
        await settle()
        precondition(store.histories["cpu"]?.values == history, "alerts leave histories untouched")
        let visible = store.beginDemand()
        await until("visible demand switches to full sampler") { probe.count > initialCount }
        let alertCount = alertProbe.count
        for _ in 0..<3 {
            let fullCount = probe.count
            await naps.end()
            await until("full sampler runs after each nap") { probe.count > fullCount }
        }
        precondition(alertProbe.count == alertCount, "page demand stops alert sampler")
        visible.cancel()
        print("PASS: alerts-only demand skips full sampler; visible demand resumes it")
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

        let pace = Naps()
        let continuity = MonitorStore(sleep: { _ in
            // Kernel counters tick every 10 ms, so a rate needs real time between two samples.
            try await Task.sleep(for: .milliseconds(100))
            try await pace.nap()
        })
        continuity.start()
        let background = continuity.beginDemand(alertsOnly: true)
        await pace.end()
        await until("second alerts-only sample has a CPU rate") { continuity.latest.cpu?.usage != nil }
        var continuityCalls = 0
        let continuityAlerts = MonitorAlerts { _ in continuityCalls += 1 }
        let continuityRules: [MonitorAlertRule.Metric: MonitorAlertRule] = [
            .cpu: .init(direction: .above, threshold: -1, recoverValue: -2, sustainCount: 2)
        ]
        continuityAlerts.evaluate(continuity.latest, rules: continuityRules, enabled: true,
                                  demand: 1, at: Date())
        await until("store naps before the page opens") { pace.isParked }
        let page = continuity.beginDemand()
        await until("first page sample") { !continuity.histories.isEmpty }
        precondition(continuity.latest.cpu?.usage != nil, "first page sample retains CPU baseline")
        precondition(continuity.latest.network.map { $0.downBytesPerSecond != nil } ?? true,
                     "first page sample retains network baseline")
        precondition(continuity.latest.disk.allSatisfy { $0.readBytesPerSecond != nil },
                     "first page sample retains disk baseline")
        continuityAlerts.evaluate(continuity.latest, rules: continuityRules, enabled: true,
                                  demand: 2, at: Date())
        precondition(continuityCalls == 1, "page opening preserves CPU breach streak")
        page.cancel()
        background.cancel()
        continuity.stop()
        print("PASS: first page sample has continuous rates and CPU alert streak")

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
