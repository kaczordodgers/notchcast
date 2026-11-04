// notchcast-sources: Tinycast/Features/SystemMonitor/Model/*.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Service/*.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Store/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Model/*.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityPreferences.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityStore.swift
// notchcast-sources: Tinycast/Features/Notchcast/Root/*.swift Tinycast/Platform/ProcessExit.swift
import Foundation

@main
@MainActor
struct MonitorModuleTests {
    static func main() async {
        let suite = "monitor-module-test-" + UUID().uuidString
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let store = MonitorStore(sample: { MonitorSnapshot() })
        let fans = FanControl(runner: { _ in })
        let module = MonitorModule(preferences: preferences, store: store, fans: fans)
        preferences.fanMode = "max"
        preferences.set(.fanControl, true)
        module.start()
        module.start()
        await fans.waitUntilIdle()
        precondition(fans.mode == .max)
        preferences.set(.fanControl, false)
        for _ in 0..<200 { await Task.yield() }
        await fans.waitUntilIdle()
        precondition(fans.mode == .auto)
        preferences.set(.fanControl, true)
        for _ in 0..<200 { await Task.yield() }
        await fans.waitUntilIdle()
        precondition(fans.mode == .max)
        module.stop()
        module.stop()
        await fans.waitUntilIdle()
        precondition(fans.mode == .auto && preferences.fanMode == "max")
        preferences.fanMode = "medium"
        for _ in 0..<200 { await Task.yield() }
        precondition(fans.mode == .auto)
        print("PASS: module start, switch off, restart, stop and stale observation; fakes only")
    }
}
