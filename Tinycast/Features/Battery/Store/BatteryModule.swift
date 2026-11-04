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
    private(set) var needsHelperUpdate = false
    private(set) var helperInstalled = false
    private(set) var chargingUnsupported = false
    private(set) var nativeLimit: Int?
    private var helperHasNativeLimit = true
    var nativeLimitAvailable: Bool {
        helperInstalled && !helperGateClosed && helperHasNativeLimit && runner.supports("charge-limit-read")
            && runner.supports("charge-limit-off")
            && NotchcastPreferences.chargeLimits.allSatisfy { runner.supports("charge-limit-\($0)") }
    }
    @ObservationIgnored private var limitGeneration = 0
    @ObservationIgnored private var observationID: UUID?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

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
    @ObservationIgnored private var launchRepair = false
    @ObservationIgnored private var versionReadFailed = false
    @ObservationIgnored private var wasOnBattery: Bool?
    @ObservationIgnored private var helperGateClosed = true
    @ObservationIgnored private var journal: BatteryOwnershipJournal
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var reschedule = false
    private(set) var failure: Error?

    init(preferences: NotchcastPreferences, runner: Runner) {
        self.preferences = preferences
        self.runner = runner
        journal = preferences.batteryJournalData.flatMap {
            try? JSONDecoder().decode(BatteryOwnershipJournal.self, from: $0)
        } ?? BatteryOwnershipJournal()
        if preferences.batteryOwnsNativeLimit && journal.effects["charge-limit"] == nil {
            journal.captureLimit(preferences.batteryPriorLimit == 0 ? nil : preferences.batteryPriorLimit)
            if let undo = journal.limitUndo {
                journal.adopt("charge-limit", applied: "charge-limit-\(preferences.batteryOwnedLimit)", undo: undo)
            }
        }
        launchRepair = preferences.batteryRootDirty || preferences.batteryOwnsNativeLimit
        if preferences.batteryRootDirty && preferences.batteryDirtyVerbs.isEmpty {
            preferences.batteryDirtyVerbs = ["battery-adapter", "battery-charging", "battery-sleep"]
        }
        for key in preferences.batteryDirtyVerbs {
            journal.adopt(key, applied: nil, undo: key + "-on")
        }
        if journal.effects.values.contains(where: \.failed) { failure = OwnershipFailure.retryPending }
        if preferences.isOn(.batteryCalibration) { preferences.set(.batteryCalibration, false) }
    }

    func repairAtLaunch() { schedule() }

    isolated deinit { timer?.cancel() }

    func start() {
        guard !running else { return }
        running = true
        chargingUnsupported = false
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
                guard let version = Int(version) else { throw RootHelperClient.Failure.invalidResponse }
                self.needsHelperUpdate = version < (Int(RootContract.version) ?? 3)
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
                    self.helperGateClosed = true
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
        timer?.cancel()
        reschedule = true
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.reschedule = false
                await self.evaluate(now: .now)
            } while self.reschedule
            self.task = nil
            guard self.running || self.hasRepairCandidates else { return }
            self.timer = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                self?.schedule()
            }
        }
    }

    func evaluate(now: Date) async {
        if !journal.effects.values.contains(where: \.failed) { failure = nil }
        if versionReadFailed { refreshHelper() }
        if !running {
            do { try releaseAssertions() } catch { failure = error }
        }
        if launchRepair && hasRepairCandidates {
            await repairMarkedChanges(now: now)
            launchRepair = !journal.effects.isEmpty
        }
        let on: (NotchcastFeature) -> Bool = { self.running && self.preferences.isOn($0) }
        let reading = runner.read()
        if let onBattery = reading?.onBattery {
            if wasOnBattery == true && !onBattery && preferences.batteryOwnsNativeLimit {
                journal.reapplyLimit()
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
                if on(.batteryChargeLimit) || journal.effects["charge-limit"] != nil {
                    limitGeneration += 1
                    if verb == .chargeLimitOff {
                        try await clearNativeLimit(now: now)
                    } else {
                        if !journal.capturedLimit {
                            let prior = try await runner.readLimit()
                            try Task.checkCancellation()
                            journal.captureLimit(prior)
                        }
                        guard let undo = journal.limitUndo else {
                            throw OwnershipFailure.unrestorableLimit(journal.priorLimit ?? 0)
                        }
                        try await perform(verb, key: "charge-limit", undo: undo, now: now)
                    }
                    try Task.checkCancellation()
                    if verb != .chargeLimitOff && on(.batteryChargeLimit) {
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
            guard helperInstalled && !helperGateClosed else { return }
            guard enabled || on(.lidClosedAwake) || !journal.effects.isEmpty else { return }
            var verbs: [BatteryRootVerbs] = []
            // Adapter disconnection requires a helper watchdog before it can be enabled safely.
            try ChargePlanService().apply(decision, watchdogReady: false) { verbs.append($0) }
            verbs.append(LidClosedPolicy.plan(enabled: on(.lidClosedAwake),
                                             helperReady: true, keepAwakeHolding: holding))
            for verb in verbs {
                try Task.checkCancellation()
                if reschedule { return }
                if chargingUnsupported && (verb == .chargingOn || verb == .chargingOff) { continue }
                guard runner.supports(verb.rawValue) else { continue }
                let key = verb.rawValue.components(separatedBy: "-").dropLast().joined(separator: "-")
                do {
                    try await perform(verb, key: key, undo: key + "-on", now: now,
                                      releasing: verb.rawValue.hasSuffix("-on"))
                } catch {
                    if verb == .chargingOn || verb == .chargingOff,
                       case RootHelperClient.Failure.executionFailed(RootContract.unsupportedExit) = error {
                        chargingUnsupported = true
                        preferences.set(.batteryCalibration, false)
                    }
                    if error as? RootHelperClient.Failure == .reinstallRequired { needsHelperUpdate = true }
                    failure = error
                }
            }
        } catch {
            if error as? RootHelperClient.Failure == .reinstallRequired { needsHelperUpdate = true }
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

    private func clearNativeLimit(now: Date) async throws {
        let current = try await runner.readLimit()
        try Task.checkCancellation()
        if journal.userChangedLimit(current) {
            journal.release("charge-limit")
            saveJournal()
            nativeLimit = current
            return
        }
        guard let raw = journal.limitUndo, let verb = BatteryRootVerbs(rawValue: raw) else {
            throw OwnershipFailure.unrestorableLimit(journal.priorLimit ?? 0)
        }
        let prior = journal.priorLimit
        try await perform(verb, key: "charge-limit", undo: raw, now: now, releasing: true)
        nativeLimit = prior
    }

    private enum OwnershipFailure: LocalizedError {
        case unrestorableLimit(Int), retryPending

        var errorDescription: String? {
            switch self {
            case .unrestorableLimit(let limit):
                String(localized: """
                    The previous charge limit of \(limit)% cannot be restored; \
                    the current limit remains in place.
                    """)
            case .retryPending:
                RootHelperClient.Failure.executionFailed(70).localizedDescription
            }
        }
    }

    private func saveJournal() {
        preferences.batteryJournalData = try? JSONEncoder().encode(journal)
        preferences.batteryDirtyVerbs = journal.effects.keys.filter { $0 != "charge-limit" }.sorted()
        preferences.batteryRootDirty = !preferences.batteryDirtyVerbs.isEmpty
        preferences.batteryOwnsNativeLimit = journal.effects["charge-limit"] != nil
        if let raw = journal.effects["charge-limit"]?.applied {
            preferences.batteryOwnedLimit = Int(raw.split(separator: "-").last ?? "") ?? 0
        }
    }

    private func perform(_ verb: BatteryRootVerbs, key: String, undo: String, now: Date,
                         releasing: Bool = false) async throws {
        guard journal.canRun(key, verb: verb.rawValue, now: now, releasing: releasing) else {
            if journal.effects[key]?.failed == true { throw OwnershipFailure.retryPending }
            return
        }
        journal.begin(key, verb: verb.rawValue, undo: undo)
        saveJournal()
        do {
            try await runner.root(verb)
            journal.succeed(key, verb: verb.rawValue, releasing: releasing)
            saveJournal()
        } catch {
            if releasing, case RootHelperClient.Failure.executionFailed(69) = error {
                journal.release(key)
            } else {
                journal.fail(key, now: now)
            }
            saveJournal()
            throw error
        }
    }

    private var hasRepairCandidates: Bool {
        journal.effects.contains { key, effect in
            guard effect.attempts < 6 else { return false }
            if !running { return true }
            switch key {
            case "charge-limit": return !preferences.isOn(.batteryChargeLimit)
            case "battery-charging":
                return ![NotchcastFeature.batterySailing, .batteryHeatProtection, .batteryCalibration]
                    .contains(where: { preferences.isOn($0) })
            case "battery-sleep": return !preferences.isOn(.lidClosedAwake)
            default: return true
            }
        }
    }

    private func repairMarkedChanges(now: Date) async {
        guard journal.effects.values.contains(where: {
            $0.attempts < 6 && ($0.retryAt.map { now >= $0 } ?? true)
        }) else { return }
        do {
            guard runner.installed(), (Int(try await runner.version()) ?? 0) >= 2 else { return }
            for verb in [BatteryRootVerbs.adapterOn, .chargingOn, .sleepOn] {
                let key = verb.rawValue.components(separatedBy: "-").dropLast().joined(separator: "-")
                guard journal.effects[key] != nil else { continue }
                try Task.checkCancellation()
                if running && ((key == "battery-charging" &&
                    (preferences.isOn(.batterySailing) || preferences.isOn(.batteryHeatProtection)
                     || preferences.isOn(.batteryCalibration))) ||
                    (key == "battery-sleep" && preferences.isOn(.lidClosedAwake))) {
                    continue
                }
                do {
                    try await perform(verb, key: key, undo: verb.rawValue, now: now, releasing: true)
                } catch {
                    guard case RootHelperClient.Failure.executionFailed(RootContract.unsupportedExit) = error else {
                        failure = error
                        continue
                    }
                }
            }
            if journal.effects["charge-limit"] != nil && !(running && preferences.isOn(.batteryChargeLimit)) {
                try await clearNativeLimit(now: now)
            }
        } catch { failure = error }
    }
}
