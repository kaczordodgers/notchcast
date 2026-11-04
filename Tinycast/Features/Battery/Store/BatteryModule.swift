import Foundation
import IOKit.pwr_mgt
import Observation

@MainActor
@Observable
final class BatteryModule: NotchcastModule {
    struct Runner {
        var read: () -> BatteryReading?
        var root: (BatteryRootVerbs) async throws -> Void
        var installed: () -> Bool = { RootHelperClient().isInstalled }
        var version: () async throws -> String = {
            guard case .version(let version) = try await RootHelperClient().run(.version) else {
                throw RootHelperClient.Failure.invalidResponse
            }
            return version
        }
        var create: (String) throws -> UInt32
        var release: (UInt32) throws -> Void

        static var live: Self {
            Self(read: { BatteryService().read() }, root: { command in
                guard let command = RootContract.Command(rawValue: command.rawValue) else {
                    throw RootHelperClient.Failure.invalidResponse
                }
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
    private(set) var needsHelperUpdate = true
    private(set) var helperInstalled = false
    @ObservationIgnored private var observationID: UUID?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var applied: [String: BatteryRootVerbs] = [
        "battery-adapter": .adapterOn, "battery-charging": .chargingOn, "battery-sleep": .sleepOn,
    ]

    private let preferences: NotchcastPreferences
    private let runner: Runner
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var running = false
    @ObservationIgnored private var engine = ChargeEngine()
    @ObservationIgnored private var assertions: [UInt32] = []
    @ObservationIgnored private var awakeUntil: Date?
    @ObservationIgnored private var awakeMinutes: Int?
    @ObservationIgnored private var calibrationEnabled = false
    @ObservationIgnored private var rootChanged = false
    private(set) var failure: Error?

    init(preferences: NotchcastPreferences, runner: Runner) {
        self.preferences = preferences
        self.runner = runner
    }

    func start() {
        guard !running else { return }
        running = true
        let identity = UUID()
        observationID = identity
        refreshHelper()
        observe(identity)
    }

    func stop() {
        running = false
        observationID = nil
        refreshTask?.cancel()
        schedule()
    }

    func waitUntilIdle() async { await task?.value }

    func refreshHelper() {
        refreshTask?.cancel()
        helperInstalled = runner.installed()
        needsHelperUpdate = true
        refreshTask = Task { [weak self] in
            guard let self, self.helperInstalled else { return }
            do {
                let version = try await self.runner.version()
                try Task.checkCancellation()
                self.needsHelperUpdate = (Int(version) ?? 0) < 2
                if self.running { self.schedule() }
            } catch {
                if !Task.isCancelled { self.failure = error }
            }
        }
    }

    private func observe(_ identity: UUID) {
        guard running, observationID == identity else { return }
        withObservationTracking {
            for feature in NotchcastFeature.allCases where feature.isSystemFeature {
                _ = preferences.isOn(feature)
            }
            _ = preferences.batteryChargePercent
            _ = preferences.keepAwakeMinutes
            schedule()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe(identity) }
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
            guard !needsHelperUpdate else { return }
            guard enabled || on(.lidClosedAwake) || rootChanged else { return }
            var verbs: [BatteryRootVerbs] = []
            // Adapter disconnection requires a helper watchdog before it can be enabled safely.
            try ChargePlanService().apply(decision, watchdogReady: false) { verbs.append($0) }
            verbs.append(LidClosedPolicy.plan(enabled: on(.lidClosedAwake),
                                             helperReady: true, keepAwakeHolding: holding))
            for verb in verbs {
                try Task.checkCancellation()
                let key = verb.rawValue.components(separatedBy: "-").dropLast().joined(separator: "-")
                guard applied[key] != verb else { continue }
                rootChanged = true
                try await runner.root(verb)
                applied[key] = verb
            }
            rootChanged = enabled || on(.lidClosedAwake)
            failure = nil
        } catch {
            failure = error
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
