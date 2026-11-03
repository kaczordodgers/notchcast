import Foundation
import IOKit.pwr_mgt
import Observation

@MainActor
final class BatteryModule: NotchcastModule {
    struct Runner {
        var read: () -> BatteryReading?
        var root: (RootContract.Command) async throws -> Void
        var create: (String) throws -> UInt32
        var release: (UInt32) throws -> Void

        static var live: Self {
            Self(read: { BatteryService().read() }, root: { command in
                _ = try await RootHelperClient().run(command)
            }, create: { type in
                var identifier: IOPMAssertionID = 0
                let result = IOPMAssertionCreateWithName(
                    type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                    "Notchcast Keep Awake" as CFString, &identifier)
                guard result == kIOReturnSuccess else { throw Failure.assertion(result) }
                return identifier
            }, release: { identifier in
                let result = IOPMAssertionRelease(identifier)
                guard result == kIOReturnSuccess else { throw Failure.assertion(result) }
            })
        }
    }

    enum Failure: Error { case assertion(IOReturn) }
    static var needsHelperUpdate: Bool {
        BatteryRootVerbs.allCases.contains { RootContract.Command(rawValue: $0.rawValue) == nil }
    }

    private let preferences: NotchcastPreferences
    private let runner: Runner
    private var task: Task<Void, Never>?
    private var running = false
    private var engine = ChargeEngine()
    private var assertions: [UInt32] = []
    private var awakeUntil: Date?
    private var awakeMinutes: Int?
    private var calibrationEnabled = false
    private var rootChanged = false
    private(set) var failure: Error?

    init(preferences: NotchcastPreferences, runner: Runner) {
        self.preferences = preferences
        self.runner = runner
    }

    func start() {
        guard !running else { return }
        running = true
        observe()
    }

    func stop() {
        running = false
        schedule()
    }

    func waitUntilIdle() async { await task?.value }

    private func observe() {
        guard running else { return }
        withObservationTracking {
            for feature in NotchcastFeature.allCases where feature.isSystemFeature {
                _ = preferences.isOn(feature)
            }
            _ = preferences.batteryChargePercent
            _ = preferences.keepAwakeMinutes
            schedule()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
    }

    private func schedule() {
        let previous = task
        previous?.cancel()
        task = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            repeat {
                await self.evaluate(now: .now)
                guard self.running, !Task.isCancelled else { return }
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            } while !Task.isCancelled
        }
    }

    func evaluate(now: Date) async {
        let on: (NotchcastFeature) -> Bool = { self.running && self.preferences.isOn($0) }
        let reading = runner.read()
        let percent = reading?.percent.map { Int($0) }
        if on(.keepAwake) {
            if awakeMinutes != preferences.keepAwakeMinutes {
                awakeMinutes = preferences.keepAwakeMinutes
                awakeUntil = now.addingTimeInterval(Double(preferences.keepAwakeMinutes * 60))
            }
        } else {
            awakeMinutes = nil
            awakeUntil = nil
        }
        let awake = KeepAwakePolicy(enabled: on(.keepAwake), until: awakeUntil)
        let holding = awake.evaluate(now: now, onBattery: reading?.onBattery ?? false,
                                     percent: percent, locked: false) == .hold
        do {
            if holding && assertions.isEmpty {
                assertions = try KeepAwakePlanService().acquire(
                    types: awake.assertionTypes, create: runner.create, release: runner.release)
            } else if !holding {
                try releaseAssertions()
            }
            if on(.batteryCalibration) && !calibrationEnabled { engine.calibration.start() }
            if !on(.batteryCalibration) { engine.calibration.cancel() }
            calibrationEnabled = on(.batteryCalibration)
            let enabled = on(.batteryChargeLimit) || on(.batterySailing)
                || on(.batteryHeatProtection) || on(.batteryCalibration)
            let policy = ChargePolicy(enabled: enabled,
                                      limit: on(.batteryChargeLimit) || on(.batterySailing)
                                        ? preferences.batteryChargePercent : 100,
                                      drain: on(.batterySailing))
            let decision = engine.evaluate(
                policy: policy, percent: percent, charging: reading?.isCharging ?? false,
                connected: reading.map { !$0.onBattery } ?? false,
                celsius: reading?.temperatureCelsius, now: now,
                heatEnabled: on(.batteryHeatProtection))
            guard !Self.needsHelperUpdate else { return }
            guard enabled || on(.lidClosedAwake) || rootChanged else { return }
            var verbs: [BatteryRootVerbs] = []
            // Adapter disconnection requires a helper watchdog before it can be enabled safely.
            try ChargePlanService().apply(decision, watchdogReady: false) { verbs.append($0) }
            verbs.append(LidClosedPolicy.plan(enabled: on(.lidClosedAwake),
                                             helperReady: true, keepAwakeHolding: holding))
            for verb in verbs {
                try Task.checkCancellation()
                guard let command = RootContract.Command(rawValue: verb.rawValue) else { continue }
                rootChanged = true
                try await runner.root(command)
            }
            rootChanged = enabled || on(.lidClosedAwake)
            failure = nil
        } catch {
            failure = error
            if rootChanged {
                var restored = true
                for verb in [BatteryRootVerbs.adapterOn, .chargingOn, .sleepOn] {
                    guard let command = RootContract.Command(rawValue: verb.rawValue) else { continue }
                    do { try await runner.root(command) } catch { restored = false }
                }
                rootChanged = !restored
            }
        }
    }

    private func releaseAssertions() throws {
        var remaining: [UInt32] = []
        try KeepAwakePlanService().release(assertions) { identifier in
            do { try runner.release(identifier) } catch {
                remaining.append(identifier)
            }
        }
        assertions = remaining
    }
}
