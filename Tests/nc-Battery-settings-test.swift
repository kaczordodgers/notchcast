// notchcast-sources: Tinycast/Features/Battery/Model/*.swift
// notchcast-kit: core root platform
// notchcast-sources: Tinycast/Features/Battery/Service/*.swift Tinycast/Features/Battery/Store/*.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Model/*.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityPreferences.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityStore.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Model/BatteryReading.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Service/BatteryService.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Service/PowerRegistryAccess.swift
import Foundation

@main
@MainActor
struct BatterySettingsTests {
    static func main() async {
        for (enabled, available, expected) in [
            (false, false, false), (true, false, true), (false, true, true), (true, true, true)
        ] {
            precondition(BatterySettingsPolicy.chargeLimitAvailable(
                enabled: enabled, nativeLimitAvailable: available) == expected)
        }
        let suite = "battery-settings-test.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        var installed = false
        let module = BatteryModule(preferences: preferences, runner: .init(read: { nil },
            root: { _ in }, installed: { installed }, version: { RootContract.version },
            create: { _ in throw RootHelperClient.Failure.timedOut }, release: { _ in }, readLimit: { nil }))
        module.start()
        precondition(!BatterySettingsPolicy.chargeLimitAvailable(
            enabled: preferences.isOn(.batteryChargeLimit), nativeLimitAvailable: module.nativeLimitAvailable))
        preferences.set(.batteryChargeLimit, true)
        precondition(BatterySettingsPolicy.chargeLimitAvailable(
            enabled: preferences.isOn(.batteryChargeLimit), nativeLimitAvailable: module.nativeLimitAvailable))
        preferences.set(.keepAwake, true)
        await module.evaluate(now: .now)
        precondition(!module.helperInstalled && module.failure as? RootHelperClient.Failure == .timedOut)
        preferences.set(.batteryChargeLimit, false)
        installed = true
        module.refreshHelper()
        for _ in 0..<100 { await Task.yield() }
        precondition(module.nativeLimitAvailable && BatterySettingsPolicy.chargeLimitAvailable(
            enabled: preferences.isOn(.batteryChargeLimit), nativeLimitAvailable: module.nativeLimitAvailable))
        module.stop()
        await module.waitUntilIdle()
        print("PASS: absent helper blocks enabling, saved ON allows disabling, verified helper allows both")
    }
}
