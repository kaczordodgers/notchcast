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
        var supports: (String) -> Bool = { RootContract.Command(rawValue: $0) != nil }
        var readLimit: () async throws -> Int? = {
            guard let command = RootContract.Command(rawValue: "charge-limit-read") else {
                throw RootHelperClient.Failure.invalidResponse
            }
            guard case .chargeLimit(let limit) = try await RootHelperClient().run(command) else {
                throw RootHelperClient.Failure.invalidResponse
            }
            return limit
        }

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
    private(set) var chargingUnsupported = false
    private(set) var nativeLimit: Int?
    private var helperHasNativeLimit = true
    var nativeLimitAvailable: Bool {
        helperInstalled && !needsHelperUpdate && helperHasNativeLimit && runner.supports("charge-limit-read")
            && runner.supports("charge-limit-off")
            && NotchcastPreferences.chargeLimits.allSatisfy { runner.supports("charge-limit-\($0)") }
    }
    @ObservationIgnored private var appliedLimit: String?
    @ObservationIgnored private var limitGeneration = 0
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
    @ObservationIgnored private var awakePaused = false
    @ObservationIgnored private var calibrationEnabled = false
    @ObservationIgnored private var rootChanged = false
    @ObservationIgnored private var launchRepair = false
    @ObservationIgnored private var versionReadFailed = false
    @ObservationIgnored private var wasOnBattery: Bool?
    @ObservationIgnored private var helperGateClosed = false
    @ObservationIgnored private var nativeCleanupAttempted = false
    private(set) var failure: Error?

    init(preferences: NotchcastPreferences, runner: Runner) {
        self.preferences = preferences
        self.runner = runner
        launchRepair = preferences.batteryRootDirty || preferences.batteryOwnsNativeLimit
        if preferences.batteryRootDirty && preferences.batteryDirtyVerbs.isEmpty {
            preferences.batteryDirtyVerbs = ["battery-adapter", "battery-charging", "battery-sleep"]
        }
        if preferences.isOn(.batteryCalibration) { preferences.set(.batteryCalibration, false) }
    }

    func repairAtLaunch() { schedule() }

    func start() {
        guard !running else { return }
        running = true
        chargingUnsupported = false
        appliedLimit = nil
        let identity = UUID()
        observationID = identity
        refreshHelper()
        observe(identity)
    }

    func stop() {
        running = false
        observationID = nil
        refreshTask?.cancel()
        launchRepair = true
        schedule()
    }

    func waitUntilIdle() async { await task?.value }

    func toggleKeepAwake() {
        guard running, preferences.isOn(.keepAwake) else { return }
        awakePaused = !assertions.isEmpty
        awakeMinutes = nil
        schedule()
    }

    func refreshHelper() {
        refreshTask?.cancel()
        helperInstalled = runner.installed()
        if !helperInstalled { helperGateClosed = true }
        helperHasNativeLimit = true
        refreshTask = Task { [weak self] in
            guard let self, self.helperInstalled else { return }
            do {
                let version = try await self.runner.version()
                try Task.checkCancellation()
                self.needsHelperUpdate = (Int(version) ?? 0) < 2
                if self.helperGateClosed && !self.needsHelperUpdate { self.launchRepair = true }
                self.helperGateClosed = self.needsHelperUpdate
                self.versionReadFailed = false
                if self.nativeLimitAvailable {
                    let generation = self.limitGeneration
                    let limit = try await self.runner.readLimit()
                    try Task.checkCancellation()
                    if generation == self.limitGeneration { self.nativeLimit = limit }
                }
                if self.running { self.schedule() }
            } catch {
                if case RootHelperClient.Failure.executionFailed(RootContract.usageExit) = error {
                    self.helperHasNativeLimit = false
                    if self.running { self.schedule() }
                    return
                }
                if !Task.isCancelled {
                    self.needsHelperUpdate = false
                    self.versionReadFailed = true
                }
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
        failure = nil
        if versionReadFailed { refreshHelper() }
        if !running {
            do { try releaseAssertions() } catch { failure = error }
        }
        if launchRepair {
            launchRepair = false
            await repairMarkedChanges()
            if !running { rootChanged = false }
        }
        let on: (NotchcastFeature) -> Bool = { self.running && self.preferences.isOn($0) }
        let reading = runner.read()
        if let onBattery = reading?.onBattery {
            if wasOnBattery == true && !onBattery && preferences.batteryOwnsNativeLimit {
                appliedLimit = nil
            }
            wasOnBattery = onBattery
        }
        let percent = reading?.percent.map { Int($0) }
        if !on(.keepAwake) { awakePaused = false }
        if on(.keepAwake) && !awakePaused {
            if awakeMinutes != preferences.keepAwakeMinutes {
                awakeMinutes = preferences.keepAwakeMinutes
                awakeUntil = now.addingTimeInterval(Double(preferences.keepAwakeMinutes * 60))
            }
        } else {
            awakeMinutes = nil
            awakeUntil = nil
        }
        let awake = KeepAwakePolicy(enabled: on(.keepAwake) && !awakePaused, until: awakeUntil)
        let holding = awake.evaluate(now: now, onBattery: reading?.onBattery ?? false,
                                     percent: percent, locked: false) == .hold
        do {
            if nativeLimitAvailable {
                guard let verb = on(.batteryChargeLimit)
                    ? BatteryRootVerbs(rawValue: "charge-limit-\(preferences.batteryChargePercent)")
                    : .chargeLimitOff else { return }
                if appliedLimit != verb.rawValue
                    && (on(.batteryChargeLimit) || (preferences.batteryOwnsNativeLimit && !nativeCleanupAttempted)) {
                    limitGeneration += 1
                    appliedLimit = nil
                    if verb == .chargeLimitOff {
                        nativeCleanupAttempted = true
                        try await clearNativeLimit()
                    } else {
                        nativeCleanupAttempted = false
                        if !preferences.batteryOwnsNativeLimit {
                            let prior = try await runner.readLimit()
                            try Task.checkCancellation()
                            preferences.batteryPriorLimit = prior ?? 0
                        }
                        preferences.batteryOwnedLimit = Int(verb.rawValue.components(separatedBy: "-").last ?? "") ?? 0
                        preferences.batteryOwnsNativeLimit = true
                        try await runner.root(verb)
                    }
                    try Task.checkCancellation()
                    appliedLimit = verb.rawValue
                    preferences.batteryOwnsNativeLimit = verb != .chargeLimitOff
                    if verb != .chargeLimitOff {
                        nativeLimit = Int(verb.rawValue.components(separatedBy: "-").last ?? "")
                    }
                }
            }
        } catch {
            failure = error
        }
        do {
            if holding && assertions.isEmpty {
                assertions = try KeepAwakePlanService().acquire(
                    types: awake.assertionTypes, create: runner.create, release: runner.release)
            } else if !holding {
                try releaseAssertions()
            }
        } catch {
            failure = error
        }
        do {
            if chargingUnsupported { preferences.set(.batteryCalibration, false) }
            if on(.batteryCalibration) && !calibrationEnabled { engine.calibration.start() }
            if !on(.batteryCalibration) { engine.calibration.cancel() }
            calibrationEnabled = on(.batteryCalibration)
            let enabled = !chargingUnsupported && (on(.batterySailing)
                || on(.batteryHeatProtection) || on(.batteryCalibration))
            let policy = ChargePolicy(enabled: enabled,
                                      limit: on(.batterySailing)
                                        ? preferences.batteryChargePercent : 100,
                                      drain: on(.batterySailing))
            let decision = engine.evaluate(
                policy: policy, percent: percent, charging: reading?.isCharging ?? false,
                connected: reading.map { !$0.onBattery } ?? false,
                celsius: reading?.temperatureCelsius, now: now,
                heatEnabled: on(.batteryHeatProtection))
            if calibrationEnabled && engine.calibration.completedAt != nil {
                preferences.batteryCalibrationCompletedAt = engine.calibration.completedAt
                preferences.set(.batteryCalibration, false)
                calibrationEnabled = false
            }
            guard helperInstalled && !needsHelperUpdate else { return }
            guard enabled || on(.lidClosedAwake) || rootChanged else { return }
            var verbs: [BatteryRootVerbs] = []
            // Adapter disconnection requires a helper watchdog before it can be enabled safely.
            try ChargePlanService().apply(decision, watchdogReady: false) { verbs.append($0) }
            verbs.append(LidClosedPolicy.plan(enabled: on(.lidClosedAwake),
                                             helperReady: true, keepAwakeHolding: holding))
            for verb in verbs {
                try Task.checkCancellation()
                if chargingUnsupported && (verb == .chargingOn || verb == .chargingOff) { continue }
                guard runner.supports(verb.rawValue) else { continue }
                let key = verb.rawValue.components(separatedBy: "-").dropLast().joined(separator: "-")
                guard applied[key] != verb else { continue }
                rootChanged = true
                preferences.batteryRootDirty = true
                if !preferences.batteryDirtyVerbs.contains(key) { preferences.batteryDirtyVerbs.append(key) }
                applied[key] = nil
                do {
                    try await runner.root(verb)
                } catch {
                    if verb == .chargingOn || verb == .chargingOff,
                       case RootHelperClient.Failure.executionFailed(RootContract.unsupportedExit) = error {
                        chargingUnsupported = true
                        preferences.batteryDirtyVerbs.removeAll { $0 == key }
                        preferences.batteryRootDirty = !preferences.batteryDirtyVerbs.isEmpty
                        preferences.set(.batteryCalibration, false)
                    }
                    throw error
                }
                applied[key] = verb
                if verb == .adapterOn || verb == .chargingOn || verb == .sleepOn {
                    preferences.batteryDirtyVerbs.removeAll { $0 == key }
                }
            }
            rootChanged = enabled || on(.lidClosedAwake)
            if applied["battery-adapter"] == .adapterOn,
               applied["battery-charging"] == .chargingOn,
               applied["battery-sleep"] == .sleepOn {
                preferences.batteryRootDirty = false
            }
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

    private func clearNativeLimit() async throws {
        let ours = preferences.batteryOwnedLimit
        let current = try await runner.readLimit()
        try Task.checkCancellation()
        if ours > 0 && current == ours {
            do { try await runner.root(.chargeLimitOff) } catch {
                guard case RootHelperClient.Failure.executionFailed(RootContract.unsupportedExit) = error else {
                    throw error
                }
            }
            nativeLimit = nil
        } else {
            nativeLimit = current
        }
        try Task.checkCancellation()
        preferences.batteryOwnsNativeLimit = false
        preferences.batteryOwnedLimit = 0
    }

    private func repairMarkedChanges() async {
        do {
            guard runner.installed(), (Int(try await runner.version()) ?? 0) >= 2 else { return }
            for verb in [BatteryRootVerbs.adapterOn, .chargingOn, .sleepOn] {
                let key = verb.rawValue.components(separatedBy: "-").dropLast().joined(separator: "-")
                guard preferences.batteryDirtyVerbs.contains(key) else { continue }
                try Task.checkCancellation()
                if running && ((key == "battery-charging" &&
                    (preferences.isOn(.batterySailing) || preferences.isOn(.batteryHeatProtection)
                     || preferences.isOn(.batteryCalibration))) ||
                    (key == "battery-sleep" && preferences.isOn(.lidClosedAwake))) {
                    applied[key] = nil
                    rootChanged = true
                    continue
                }
                do {
                    try await runner.root(verb)
                    applied[key] = verb
                } catch {
                    guard case RootHelperClient.Failure.executionFailed(RootContract.unsupportedExit) = error else {
                        continue
                    }
                }
                preferences.batteryDirtyVerbs.removeAll { $0 == key }
            }
            preferences.batteryRootDirty = !preferences.batteryDirtyVerbs.isEmpty
            if preferences.batteryOwnsNativeLimit && !(running && preferences.isOn(.batteryChargeLimit)) {
                nativeCleanupAttempted = true
                try await clearNativeLimit()
                appliedLimit = nil
            }
        } catch {}
    }
}
