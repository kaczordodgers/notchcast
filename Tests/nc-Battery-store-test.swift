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
        let suite = "battery-store-test.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        for feature in NotchcastFeature.allCases where feature.isSystemFeature {
            precondition(!preferences.isOn(feature))
        }
        preferences.batteryChargePercent = 45
        precondition(preferences.batteryChargePercent == 80)
        preferences.batteryChargePercent = 100
        precondition(preferences.batteryChargePercent == 100)
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
        }, release: { released.append($0) }))
        preferences.set(.keepAwake, true)
        preferences.set(.batteryChargeLimit, true)
        module.start()
        await module.evaluate(now: .now)
        precondition(created == 2)
        precondition(module.needsHelperUpdate && rootCalls == 0)
        preferences.set(.keepAwake, false)
        await module.evaluate(now: .now)
        precondition(released.sorted() == [1, 2])
        reading = nil
        preferences.set(.keepAwake, true)
        await module.evaluate(now: .now)
        precondition(created == 4)
        module.stop()
        await module.waitUntilIdle()
        precondition(released.sorted() == [1, 2, 3, 4])
        precondition(rootCalls == 0)
        var calls: [BatteryRootVerbs] = []
        var fail = false
        let modern = BatteryModule(preferences: preferences, runner: .init(read: {
            BatteryReading.decode(properties: ["CurrentCapacity": 85, "MaxCapacity": 100,
                                               "ExternalConnected": true])
        }, root: {
            calls.append($0)
            if fail { throw RootHelperClient.Failure.timedOut }
        }, installed: { true }, version: { "2" }, create: { _ in 99 }, release: { _ in }))
        preferences.set(.keepAwake, false)
        preferences.set(.batterySailing, true)
        preferences.batteryChargePercent = 80
        modern.start()
        for _ in 0..<100 { await Task.yield() }
        await modern.evaluate(now: .now)
        precondition(!modern.needsHelperUpdate && calls == [.chargingOff])
        await modern.evaluate(now: .now)
        precondition(calls == [.chargingOff])
        preferences.set(.lidClosedAwake, true)
        preferences.set(.keepAwake, true)
        fail = true
        calls = []
        await modern.evaluate(now: .now)
        precondition(modern.failure != nil && calls == [.sleepOff])
        modern.stop()
        await modern.waitUntilIdle()
        print("PASS: default-off switches, option bounds, missing verbs no-op, switch-off and quit release")
    }
}
