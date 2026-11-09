// notchcast-sources: Tinycast/Features/Battery/Model/*.swift Tinycast/Features/Battery/Service/*.swift
// notchcast-sources: Tinycast/Features/Battery/Store/*.swift Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Model/*.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityPreferences.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityStore.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Root/*.swift Tinycast/Platform/ProcessExit.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Model/BatteryReading.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Service/BatteryService.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Service/PowerRegistryAccess.swift
import Foundation

@main
@MainActor
struct BatteryStoreTests {
    static func main() async {
        await followupCases()
        await roundThreeCases()
        await safetyCases()
        let suite = "battery-store-test.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        for feature in NotchcastFeature.allCases where feature.isSystemFeature {
            precondition(!preferences.isOn(feature))
        }
        preferences.batteryChargePercent = 45
        precondition(preferences.batteryChargePercent == 60)
        preferences.batteryChargePercent = 100
        precondition(preferences.batteryChargePercent == 90)
        let defaults = UserDefaults(suiteName: suite)!
        for enabled in [false, true] {
            defaults.set(enabled, forKey: NotchcastFeature.batteryChargeLimit.rawValue)
            for (stored, expected) in [(100, 90), (85, 80), (65, 60), (50, 60)] {
                defaults.set(stored, forKey: "batteryChargePercent")
                let restored = NotchcastPreferences(suiteName: suite)
                precondition(restored.isOn(.batteryChargeLimit) == enabled)
                precondition(restored.batteryChargePercent == expected)
            }
        }
        defaults.set(false, forKey: NotchcastFeature.batteryChargeLimit.rawValue)
        preferences.keepAwakeMinutes = -1
        precondition(preferences.keepAwakeMinutes == 60)
        precondition(NotchcastPreferences(suiteName: suite).keepAwakeMinutes == 60)
        var created = 0
        var released: [UInt32] = []
        var rootCalls = 0
        var reading = BatteryReading.decode(properties: ["CurrentCapacity": 90, "MaxCapacity": 100,
                                                        "ExternalConnected": true])
        let module = BatteryModule(preferences: preferences, runner: .init(read: { reading },
            root: { _ in rootCalls += 1 }, installed: { true }, version: { "1" }, create: { _ in
            created += 1
            return UInt32(created)
        }, release: { released.append($0) }, readLimit: {
            preconditionFailure("Old helper must never read the native limit")
        }))
        preferences.set(.keepAwake, true)
        preferences.set(.batteryChargeLimit, true)
        module.start()
        for _ in 0..<100 { await Task.yield() }
        await module.evaluate(now: .now)
        precondition(created == 2)
        precondition(module.needsHelperUpdate && rootCalls == 0)
        module.toggleKeepAwake()
        await module.evaluate(now: .now)
        precondition(released.sorted() == [1, 2])
        module.toggleKeepAwake()
        await module.evaluate(now: .now)
        precondition(created == 4)
        preferences.set(.keepAwake, false)
        await module.evaluate(now: .now)
        precondition(released.sorted() == [1, 2, 3, 4])
        reading = nil
        preferences.set(.keepAwake, true)
        await module.evaluate(now: .now)
        precondition(created == 6)
        module.stop()
        await module.waitUntilIdle()
        precondition(released.sorted() == [1, 2, 3, 4, 5, 6])
        precondition(rootCalls == 0)
        var calls: [RootContract.Command] = []
        var fail = false
        var currentLimit: Int? = 70
        let modern = BatteryModule(preferences: preferences, runner: .init(read: {
            BatteryReading.decode(properties: ["CurrentCapacity": 85, "MaxCapacity": 100,
                                               "ExternalConnected": true])
        }, root: {
            calls.append($0)
            if fail { throw RootHelperClient.Failure.timedOut }
            if $0.rawValue.hasPrefix("charge-limit-") {
                currentLimit = Int($0.rawValue.components(separatedBy: "-").last ?? "")
            }
        }, installed: { true }, version: { RootContract.version }, create: { _ in 99 }, release: { _ in },
           supports: { _ in true }, readLimit: { currentLimit }))
        preferences.set(.keepAwake, false)
        preferences.set(.batterySailing, true)
        preferences.batteryChargePercent = 80
        modern.start()
        for _ in 0..<100 { await Task.yield() }
        await modern.evaluate(now: .now)
        precondition(!modern.needsHelperUpdate && calls == [.chargeLimit80, .batteryChargingOff])
        await modern.evaluate(now: .now)
        precondition(calls == [.chargeLimit80, .batteryChargingOff])
        for percent in NotchcastPreferences.chargeLimits {
            preferences.batteryChargePercent = percent
            await modern.evaluate(now: .now)
            precondition(calls.last?.rawValue == "charge-limit-\(percent)")
        }
        preferences.set(.batteryChargeLimit, false)
        await modern.evaluate(now: .now)
        precondition(calls.last == .chargeLimit70 && modern.nativeLimit == 70)
        preferences.set(.lidClosedAwake, true)
        preferences.set(.keepAwake, true)
        fail = true
        calls = []
        await modern.evaluate(now: .now)
        precondition(modern.failure != nil && calls == [.batterySleepOff])
        modern.stop()
        await modern.waitUntilIdle()
        preferences.set(.batterySailing, true)
        preferences.set(.batteryHeatProtection, true)
        preferences.set(.lidClosedAwake, false)
        preferences.set(.keepAwake, false)
        var attempts = 0
        let unsupported = BatteryModule(preferences: preferences, runner: .init(read: {
            BatteryReading.decode(properties: ["CurrentCapacity": 95, "MaxCapacity": 100,
                                               "ExternalConnected": true])
        }, root: { verb in
            if verb == .batteryChargingOff {
                attempts += 1
                throw RootHelperClient.Failure.executionFailed(70)
            }
        }, installed: { true }, version: { RootContract.version }, create: { _ in 0 }, release: { _ in },
           supports: { _ in true }, readLimit: { nil }))
        unsupported.start()
        for _ in 0..<100 { await Task.yield() }
        await unsupported.evaluate(now: .now)
        await unsupported.evaluate(now: .now)
        precondition(!unsupported.chargingUnsupported && attempts == 1 && unsupported.failure != nil)
        unsupported.stop()
        await unsupported.waitUntilIdle()
        for feature in NotchcastFeature.allCases where feature.isSystemFeature {
            preferences.set(feature, false)
        }
        var cleanupCalls: [RootContract.Command] = []
        let leftover = BatteryModule(preferences: preferences, runner: .init(read: { nil },
            root: { cleanupCalls.append($0) }, installed: { true }, version: { RootContract.version },
            create: { _ in preconditionFailure("No assertions expected") }, release: { _ in },
            supports: { _ in true }, readLimit: { 85 }))
        leftover.start()
        for _ in 0..<100 { await Task.yield() }
        await leftover.evaluate(now: .now)
        precondition(cleanupCalls.isEmpty && leftover.nativeLimit == 85)
        await leftover.evaluate(now: .now)
        precondition(cleanupCalls.isEmpty)
        leftover.stop()
        await leftover.waitUntilIdle()
        precondition(cleanupCalls.isEmpty)
        var missingCalls = 0
        preferences.set(.batteryChargeLimit, true)
        let missing = BatteryModule(preferences: preferences, runner: .init(read: { nil },
            root: { _ in missingCalls += 1 }, installed: { true }, version: { RootContract.version },
            create: { _ in 0 }, release: { _ in }, supports: { _ in false },
            readLimit: { preconditionFailure("Missing read verb must never run") }))
        missing.start()
        for _ in 0..<100 { await Task.yield() }
        await missing.evaluate(now: .now)
        precondition(!missing.nativeLimitAvailable && missingCalls == 0)
        missing.stop()
        await missing.waitUntilIdle()
        for feature in NotchcastFeature.allCases where feature.isSystemFeature {
            preferences.set(feature, false)
        }
        preferences.batteryJournalData = nil
        preferences.batteryDirtyVerbs = []
        preferences.batteryPriorLimit = 0
        preferences.batteryRootDirty = true
        preferences.batteryOwnsNativeLimit = true
        preferences.batteryOwnedLimit = 80
        var repairCalls: [RootContract.Command] = []
        let repair = BatteryModule(preferences: preferences, runner: .init(read: { nil },
            root: { repairCalls.append($0) }, installed: { true }, version: { RootContract.version },
            create: { _ in 0 }, release: { _ in }, readLimit: { 80 }))
        repair.repairAtLaunch()
        await repair.waitUntilIdle()
        precondition(repairCalls == [.batteryAdapterOn, .batteryChargingOn, .batterySleepOn, .chargeLimitOff])
        precondition(!preferences.batteryRootDirty && !preferences.batteryOwnsNativeLimit)
        preferences.set(.batterySailing, true)
        let stop = BatteryModule(preferences: preferences, runner: .init(read: {
            BatteryReading.decode(properties: ["CurrentCapacity": 95, "MaxCapacity": 100,
                                               "ExternalConnected": true])
        }, root: { repairCalls.append($0) }, installed: { true }, version: { RootContract.version },
           create: { _ in 0 }, release: { _ in }, readLimit: { nil }))
        stop.start()
        for _ in 0..<100 { await Task.yield() }
        await stop.evaluate(now: .now)
        precondition(preferences.batteryRootDirty)
        stop.refreshHelper()
        stop.stop()
        await stop.waitUntilIdle()
        precondition(!preferences.batteryRootDirty && repairCalls.last == .batteryChargingOn)
        print("PASS: stored limit rounding, startup cleanup once, missing verbs, switch-off and quit release")
    }

    static func followupCases() async {
        let suite = "battery-followup.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let prefs = NotchcastPreferences(suiteName: suite)
        prefs.set(.batteryChargeLimit, true)
        for prior in [85, 95] {
            var reads = 0
            let module = BatteryModule(preferences: prefs, runner: .init(read: { nil }, root: { _ in
                preconditionFailure("Unrestorable limits must not be overwritten")
            }, installed: { true }, version: { RootContract.version }, create: { _ in 0 }, release: { _ in },
               readLimit: { reads += 1; return prior }))
            module.start()
            for _ in 0..<100 { await Task.yield() }
            let before = reads
            await module.evaluate(now: .now)
            await module.evaluate(now: .now)
            precondition(reads == before && !prefs.batteryOwnsNativeLimit && module.failure != nil)
            module.stop()
            await module.waitUntilIdle()
        }
        prefs.set(.batteryChargeLimit, false)
        var journal = BatteryOwnershipJournal()
        journal.adopt("battery-sleep", applied: "battery-sleep-off", undo: "battery-sleep-on")
        journal.begin("battery-sleep", verb: "battery-sleep-on", undo: "battery-sleep-on")
        for _ in 0..<6 { journal.fail("battery-sleep", now: .distantPast) }
        prefs.batteryJournalData = try? JSONEncoder().encode(journal)
        var versions = 0
        let exhausted = BatteryModule(preferences: prefs, runner: .init(read: { nil }, root: { _ in
            preconditionFailure("Exhausted repair must not run")
        }, installed: { true }, version: { versions += 1; return RootContract.version },
           create: { _ in 0 }, release: { _ in }))
        exhausted.repairAtLaunch()
        await exhausted.waitUntilIdle()
        exhausted.stop()
        await exhausted.waitUntilIdle()
        precondition(versions == 0)
    }

    static func safetyCases() async {
        let suite = "battery-safety-test.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        preferences.set(.batteryCalibration, true)
        var percent = 50
        var connected = true
        var absent = false
        var calls: [RootContract.Command] = []
        var created = 0
        var released = 0
        var nativeFailure = false
        var currentLimit: Int? = 85
        var unsupported = false
        var pending: CheckedContinuation<Void, Never>?
        var suspendToggle = false
        let module = BatteryModule(preferences: preferences, runner: .init(read: {
            absent ? nil : BatteryReading.decode(properties: [
                "CurrentCapacity": percent, "MaxCapacity": 100, "ExternalConnected": connected])
        }, root: { verb in
            calls.append(verb)
            if verb == .chargeLimit80 && nativeFailure { throw RootHelperClient.Failure.timedOut }
            if verb.rawValue.hasPrefix("charge-limit-") {
                currentLimit = Int(verb.rawValue.components(separatedBy: "-").last ?? "")
            }
            if verb == .batteryChargingOff && unsupported {
                throw RootHelperClient.Failure.executionFailed(RootContract.unsupportedExit)
            }
            if verb == .batteryChargingOff && suspendToggle {
                suspendToggle = false
                await withCheckedContinuation { pending = $0 }
                try Task.checkCancellation()
            }
        }, installed: { true }, version: { RootContract.version }, create: { _ in
            created += 1
            return UInt32(created)
        }, release: { _ in released += 1 }, readLimit: { currentLimit }))
        precondition(!preferences.isOn(.batteryCalibration))
        module.start()
        for _ in 0..<100 { await Task.yield() }
        preferences.set(.keepAwake, true)
        for _ in 0..<100 { await Task.yield() }
        await module.evaluate(now: .now)
        precondition(created == 2 && module.nativeLimit == 85 && calls.isEmpty)
        preferences.set(.keepAwake, false)
        for _ in 0..<100 { await Task.yield() }
        await module.evaluate(now: .now)
        precondition(released == 2 && module.nativeLimit == 85 && calls.isEmpty)
        preferences.set(.batteryCalibration, true)
        for _ in 0..<100 { await Task.yield() }
        for value in [100, 10, 100, 100] {
            percent = value
            await module.evaluate(now: .now)
        }
        precondition(!preferences.isOn(.batteryCalibration))
        precondition(preferences.batteryCalibrationCompletedAt != nil)
        preferences.set(.batteryChargeLimit, true)
        preferences.batteryChargePercent = 80
        preferences.set(.keepAwake, true)
        nativeFailure = true
        for _ in 0..<100 { await Task.yield() }
        await module.evaluate(now: .now)
        precondition(module.failure != nil && created == 4)
        nativeFailure = false
        await module.evaluate(now: Date.now.addingTimeInterval(120))
        preferences.set(.batterySailing, true)
        percent = 95
        for _ in 0..<100 { await Task.yield() }
        await module.evaluate(now: .now)
        precondition(calls.last == .batteryChargingOff)
        let heldCalls = calls
        absent = true
        await module.evaluate(now: .now)
        absent = false
        connected = false
        percent = 20
        await module.evaluate(now: .now)
        precondition(calls == heldCalls)
        connected = true
        await module.evaluate(now: .now)
        precondition(calls.last == .batteryChargingOn)
        suspendToggle = true
        percent = 95
        let toggle = Task { await module.evaluate(now: .now) }
        while pending == nil { await Task.yield() }
        toggle.cancel()
        pending?.resume()
        await toggle.value
        preferences.set(.batterySailing, false)
        for _ in 0..<100 { await Task.yield() }
        await module.evaluate(now: .now)
        precondition(calls.last == .batteryChargingOn && !preferences.batteryRootDirty)
        module.stop()
        await module.waitUntilIdle()
        precondition(calls.last == .batteryChargingOn && module.nativeLimit == 85)
        precondition(!preferences.batteryRootDirty && released == created)
        preferences.set(.batteryChargeLimit, false)
        preferences.set(.keepAwake, false)
        preferences.set(.batteryCalibration, true)
        unsupported = true
        module.start()
        for _ in 0..<100 { await Task.yield() }
        percent = 100
        await module.evaluate(now: .now)
        await module.evaluate(now: .now)
        precondition(module.chargingUnsupported)
        precondition(!preferences.isOn(.batteryCalibration))
        let count = calls.count
        preferences.set(.batteryCalibration, true)
        await module.evaluate(now: .now)
        precondition(!preferences.isOn(.batteryCalibration))
        precondition(calls.count == count)
        module.stop()
        await module.waitUntilIdle()
        await staleReadCase()
    }

    static func staleReadCase() async {
        let suite = "battery-read-test.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        var pending: CheckedContinuation<Int?, Error>?
        var missing = false
        let module = BatteryModule(preferences: preferences, runner: .init(read: { nil },
            root: { _ in }, installed: { true }, version: { RootContract.version }, create: { _ in 0 },
            release: { _ in }, readLimit: {
                if missing { throw RootHelperClient.Failure.executionFailed(RootContract.usageExit) }
                if pending != nil { return 70 }
                return try await withCheckedThrowingContinuation { pending = $0 }
            }))
        module.start()
        while pending == nil { await Task.yield() }
        preferences.batteryChargePercent = 80
        preferences.set(.batteryChargeLimit, true)
        await module.evaluate(now: .now)
        precondition(module.nativeLimit == 80)
        pending?.resume(returning: 70)
        for _ in 0..<100 { await Task.yield() }
        precondition(module.nativeLimit == 80)
        missing = true
        module.refreshHelper()
        for _ in 0..<100 { await Task.yield() }
        precondition(!module.nativeLimitAvailable && module.failure == nil)
        module.stop()
        await module.waitUntilIdle()
    }

    static func roundThreeCases() async {
        let suite = "battery-round-three.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let prefs = NotchcastPreferences(suiteName: suite)
        prefs.batteryRootDirty = true
        var calls: [RootContract.Command] = []
        let repair = BatteryModule(preferences: prefs, runner: .init(read: { nil }, root: {
            calls.append($0)
            if $0 == .batteryAdapterOn { throw RootHelperClient.Failure.timedOut }
            if $0 == .batteryChargingOn { throw RootHelperClient.Failure.executionFailed(RootContract.unsupportedExit) }
        }, installed: { true }, version: { RootContract.version }, create: { _ in 1 }, release: { _ in }))
        repair.repairAtLaunch()
        await repair.waitUntilIdle()
        for _ in 0..<3 { await repair.evaluate(now: .now) }
        precondition(calls == [.batteryAdapterOn, .batteryChargingOn, .batterySleepOn])
        precondition(prefs.batteryDirtyVerbs == ["battery-adapter"] && repair.failure != nil)
        var version = "1"
        calls = []
        let reopening = BatteryModule(preferences: prefs, runner: .init(read: { nil },
            root: { calls.append($0) }, installed: { true }, version: { version },
            create: { _ in 1 }, release: { _ in }, readLimit: { nil }))
        reopening.start()
        for _ in 0..<100 { await Task.yield() }
        precondition(calls.isEmpty)
        version = RootContract.version
        reopening.refreshHelper()
        for _ in 0..<100 { await Task.yield() }
        await reopening.evaluate(now: Date.now.addingTimeInterval(3600))
        await reopening.evaluate(now: .now)
        precondition(calls == [.batteryAdapterOn] && !prefs.batteryRootDirty)
        reopening.stop()
        await reopening.waitUntilIdle()
        prefs.batteryRootDirty = true
        prefs.batteryDirtyVerbs = ["battery-adapter"]

        for installed in [false, true] {
            prefs.set(.keepAwake, true)
            var assertions = 0
            let unavailable = BatteryModule(preferences: prefs, runner: .init(read: { nil }, root: { _ in
                preconditionFailure("Closed gate must not write")
            }, installed: { installed }, version: { "1" }, create: { _ in assertions += 1; return UInt32(assertions) },
               release: { _ in }))
            unavailable.start()
            for _ in 0..<100 { await Task.yield() }
            await unavailable.evaluate(now: .now)
            precondition(assertions == 2)
            unavailable.stop()
            await unavailable.waitUntilIdle()
        }

        prefs.batteryRootDirty = false
        prefs.batteryDirtyVerbs = []
        prefs.set(.batteryChargeLimit, true)
        var connected = false
        var current: Int? = 85
        var failWrite = true
        calls = []
        let native = BatteryModule(preferences: prefs, runner: .init(read: {
            BatteryReading.decode(properties: ["CurrentCapacity": 90, "MaxCapacity": 100,
                                               "ExternalConnected": connected])
        }, root: {
            calls.append($0)
            if failWrite { throw RootHelperClient.Failure.timedOut }
            if connected { current = $0 == .chargeLimitOff ? nil : 80 }
        }, installed: { true }, version: { RootContract.version }, create: { _ in 1 }, release: { _ in }, readLimit: { current }))
        native.start()
        for _ in 0..<100 { await Task.yield() }
        await native.evaluate(now: .now)
        let relaunch = BatteryModule(preferences: prefs, runner: .init(read: { nil }, root: { _ in
            preconditionFailure("Unconfirmed write must not clear the user's limit on relaunch")
        }, installed: { true }, version: { RootContract.version }, create: { _ in 1 }, release: { _ in }, readLimit: { current }))
        relaunch.repairAtLaunch()
        await relaunch.waitUntilIdle()
        precondition(current == 85 && !prefs.batteryOwnsNativeLimit)
        prefs.set(.batteryChargeLimit, false)
        await native.evaluate(now: .now)
        precondition(!calls.contains(.chargeLimitOff) && current == 85 && !prefs.batteryOwnsNativeLimit)
        failWrite = false
        prefs.set(.batteryChargeLimit, true)
        await native.evaluate(now: .now)
        let beforePlug = calls.count
        connected = true
        await native.evaluate(now: .now)
        precondition(calls.count == beforePlug && current == 85)
        await native.evaluate(now: .now)
        precondition(calls.count == beforePlug)
        precondition(!prefs.batteryOwnsNativeLimit && native.failure != nil)
        native.stop()
        await native.waitUntilIdle()
        prefs.batteryJournalData = nil
        prefs.batteryRootDirty = true
        prefs.batteryDirtyVerbs = ["battery-adapter", "battery-charging", "battery-sleep"]
        prefs.batteryOwnsNativeLimit = true
        prefs.batteryOwnedLimit = 80
        prefs.set(.batteryChargeLimit, false)
        prefs.set(.batterySailing, true)
        prefs.set(.lidClosedAwake, true)
        calls = []
        let active = BatteryModule(preferences: prefs, runner: .init(read: {
            BatteryReading.decode(properties: ["CurrentCapacity": 95, "MaxCapacity": 100,
                                               "ExternalConnected": true])
        }, root: {
            calls.append($0)
            if $0 == .batteryAdapterOn || $0 == .chargeLimitOff { throw RootHelperClient.Failure.timedOut }
        }, installed: { true }, version: { RootContract.version }, create: { _ in 1 }, release: { _ in }, readLimit: { 80 }))
        active.start()
        for _ in 0..<100 { await Task.yield() }
        await active.evaluate(now: .now)
        let held = calls
        for _ in 0..<3 { await active.evaluate(now: .now) }
        precondition(calls == held && calls.contains(.batteryChargingOff) && calls.contains(.batterySleepOff))
        precondition(!calls.contains(.batteryChargingOn) && !calls.contains(.batterySleepOn))
        precondition(calls.filter { $0 == .chargeLimitOff }.count == 1)
        active.stop()
        await active.waitUntilIdle()

        prefs.batteryRootDirty = false
        prefs.batteryDirtyVerbs = []
        prefs.batteryOwnsNativeLimit = false
        prefs.batteryJournalData = nil
        prefs.set(.lidClosedAwake, false)
        var versions = 0
        var versionFails = true
        var garbledVersion = true
        calls = []
        let transient = BatteryModule(preferences: prefs, runner: .init(read: {
            BatteryReading.decode(properties: ["CurrentCapacity": 95, "MaxCapacity": 100,
                                               "ExternalConnected": true])
        }, root: { calls.append($0) }, installed: { true }, version: {
            versions += 1
            if versionFails { throw RootHelperClient.Failure.timedOut }
            return garbledVersion ? "garbled" : RootContract.version
        }, create: { _ in 1 }, release: { _ in }, readLimit: { nil }))
        transient.start()
        for _ in 0..<100 { await Task.yield() }
        precondition(!transient.needsHelperUpdate && !transient.nativeLimitAvailable)
        precondition(calls.isEmpty)
        versionFails = false
        await transient.evaluate(now: .now)
        for _ in 0..<100 { await Task.yield() }
        precondition(!transient.needsHelperUpdate && !transient.nativeLimitAvailable && calls.isEmpty)
        garbledVersion = false
        await transient.evaluate(now: .now)
        for _ in 0..<100 { await Task.yield() }
        precondition(versions >= 2 && calls.contains(.batteryChargingOff))
        prefs.set(.batterySailing, false)
        await transient.evaluate(now: .now)
        precondition(calls.last == .batteryChargingOn)
        transient.stop()
        await transient.waitUntilIdle()
    }
}
