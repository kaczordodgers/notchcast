// notchcast-sources: Tinycast/Features/Battery/Model/*.swift Tinycast/Features/Battery/Service/*.swift
// notchcast-sources: Tinycast/Features/Battery/Store/*.swift Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
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
        var calls: [BatteryRootVerbs] = []
        var fail = false
        let modern = BatteryModule(preferences: preferences, runner: .init(read: {
            BatteryReading.decode(properties: ["CurrentCapacity": 85, "MaxCapacity": 100,
                                               "ExternalConnected": true])
        }, root: {
            calls.append($0)
            if fail { throw RootHelperClient.Failure.timedOut }
        }, installed: { true }, version: { "2" }, create: { _ in 99 }, release: { _ in },
           supports: { _ in true }, readLimit: { 70 }))
        preferences.set(.keepAwake, false)
        preferences.set(.batterySailing, true)
        preferences.batteryChargePercent = 80
        modern.start()
        for _ in 0..<100 { await Task.yield() }
        await modern.evaluate(now: .now)
        precondition(!modern.needsHelperUpdate && calls == [.chargeLimit80, .chargingOff])
        await modern.evaluate(now: .now)
        precondition(calls == [.chargeLimit80, .chargingOff])
        for percent in NotchcastPreferences.chargeLimits {
            preferences.batteryChargePercent = percent
            await modern.evaluate(now: .now)
            precondition(calls.last?.rawValue == "charge-limit-\(percent)")
        }
        preferences.set(.batteryChargeLimit, false)
        await modern.evaluate(now: .now)
        precondition(calls.last == .chargeLimitOff && modern.nativeLimit == nil)
        preferences.set(.lidClosedAwake, true)
        preferences.set(.keepAwake, true)
        fail = true
        calls = []
        await modern.evaluate(now: .now)
        precondition(modern.failure != nil && calls == [.sleepOff])
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
            if verb == .chargingOff {
                attempts += 1
                throw RootHelperClient.Failure.executionFailed(70)
            }
        }, installed: { true }, version: { "2" }, create: { _ in 0 }, release: { _ in },
           supports: { _ in true }, readLimit: { nil }))
        unsupported.start()
        for _ in 0..<100 { await Task.yield() }
        await unsupported.evaluate(now: .now)
        await unsupported.evaluate(now: .now)
        precondition(!unsupported.chargingUnsupported && attempts >= 2 && unsupported.failure != nil)
        unsupported.stop()
        await unsupported.waitUntilIdle()
        for feature in NotchcastFeature.allCases where feature.isSystemFeature {
            preferences.set(feature, false)
        }
        var cleanupCalls: [BatteryRootVerbs] = []
        let leftover = BatteryModule(preferences: preferences, runner: .init(read: { nil },
            root: { cleanupCalls.append($0) }, installed: { true }, version: { "2" },
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
            root: { _ in missingCalls += 1 }, installed: { true }, version: { "2" },
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
        preferences.batteryRootDirty = true
        preferences.batteryOwnsNativeLimit = true
        var repairCalls: [BatteryRootVerbs] = []
        let repair = BatteryModule(preferences: preferences, runner: .init(read: { nil },
            root: { repairCalls.append($0) }, installed: { true }, version: { "2" },
            create: { _ in 0 }, release: { _ in }, readLimit: { nil }))
        repair.repairAtLaunch()
        await repair.waitUntilIdle()
        precondition(repairCalls == [.adapterOn, .chargingOn, .sleepOn, .chargeLimitOff])
        precondition(!preferences.batteryRootDirty && !preferences.batteryOwnsNativeLimit)
        preferences.set(.batterySailing, true)
        let stop = BatteryModule(preferences: preferences, runner: .init(read: {
            BatteryReading.decode(properties: ["CurrentCapacity": 95, "MaxCapacity": 100,
                                               "ExternalConnected": true])
        }, root: { repairCalls.append($0) }, installed: { true }, version: { "2" },
           create: { _ in 0 }, release: { _ in }, readLimit: { nil }))
        stop.start()
        for _ in 0..<100 { await Task.yield() }
        await stop.evaluate(now: .now)
        precondition(preferences.batteryRootDirty)
        stop.refreshHelper()
        stop.stop()
        await stop.waitUntilIdle()
        precondition(!preferences.batteryRootDirty && repairCalls.suffix(3) == [.adapterOn, .chargingOn, .sleepOn])
        print("PASS: stored limit rounding, startup cleanup once, missing verbs, switch-off and quit release")
    }

    static func safetyCases() async {
        let suite = "battery-safety-test.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        preferences.set(.batteryCalibration, true)
        var percent = 50
        var connected = true
        var absent = false
        var calls: [BatteryRootVerbs] = []
        var created = 0
        var released = 0
        var nativeFailure = false
        var unsupported = false
        var pending: CheckedContinuation<Void, Never>?
        var suspendToggle = false
        let module = BatteryModule(preferences: preferences, runner: .init(read: {
            absent ? nil : BatteryReading.decode(properties: [
                "CurrentCapacity": percent, "MaxCapacity": 100, "ExternalConnected": connected])
        }, root: { verb in
            calls.append(verb)
            if verb == .chargeLimit80 && nativeFailure { throw RootHelperClient.Failure.timedOut }
            if verb == .chargingOff && unsupported {
                throw RootHelperClient.Failure.executionFailed(RootContract.unsupportedExit)
            }
            if verb == .chargingOff && suspendToggle {
                suspendToggle = false
                await withCheckedContinuation { pending = $0 }
                try Task.checkCancellation()
            }
        }, installed: { true }, version: { "2" }, create: { _ in
            created += 1
            return UInt32(created)
        }, release: { _ in released += 1 }, readLimit: { 85 }))
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
        preferences.set(.batterySailing, true)
        percent = 95
        for _ in 0..<100 { await Task.yield() }
        await module.evaluate(now: .now)
        precondition(calls.last == .chargingOff)
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
        precondition(calls.last == .chargingOn)
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
        precondition(calls.last == .chargingOn && !preferences.batteryRootDirty)
        module.stop()
        await module.waitUntilIdle()
        precondition(calls.last == .chargeLimitOff)
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
        let count = calls.count
        await module.evaluate(now: .now)
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
            root: { _ in }, installed: { true }, version: { "2" }, create: { _ in 0 },
            release: { _ in }, readLimit: {
                if missing { throw RootHelperClient.Failure.executionFailed(RootContract.usageExit) }
                return try await withCheckedThrowingContinuation { pending = $0 }
            }))
        module.start()
        while pending == nil { await Task.yield() }
        preferences.batteryChargePercent = 80
        preferences.set(.batteryChargeLimit, true)
        await module.evaluate(now: .now)
        precondition(module.nativeLimit == 80)
        pending?.resume(returning: 85)
        for _ in 0..<100 { await Task.yield() }
        precondition(module.nativeLimit == 80)
        missing = true
        module.refreshHelper()
        for _ in 0..<100 { await Task.yield() }
        precondition(!module.nativeLimitAvailable && module.failure == nil)
        module.stop()
        await module.waitUntilIdle()
    }
}
