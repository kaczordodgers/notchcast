// notchcast-sources: -swift-version 6 -strict-concurrency=complete
// notchcast-kit: core
// notchcast-sources: Tinycast/Features/DictationTrigger/DictationTriggerModule.swift
import Foundation
import Observation

@MainActor @Observable
private final class Recorder {
    var active = false
    var available = true
}

@main
struct DictationTriggerLifecycleTest {
    @MainActor
    static func main() async {
        let suite = "trigger-lifecycle-\(UUID())"
        let preferences = NotchcastPreferences(suiteName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        preferences.set(.globeDictation, false)
        let recorder = Recorder()
        var reserved = false
        var configurations: [Bool] = []
        var enabledConfigurations: [Bool] = []
        var stops = 0
        let module = DictationTriggerModule(
            available: { recorder.available },
            paused: { recorder.active }, reserve: { reserved = $0 },
            configure: { enabled, paused in
                enabledConfigurations.append(enabled)
                configurations.append(enabled && paused)
            }, teardown: { stops += 1 })
        let controller = NotchcastModuleController([
            .init(requires: [.globeDictation], module: module)
        ], preferences: preferences)
        controller.run()
        precondition(configurations.isEmpty && !reserved)
        preferences.set(.island, false)
        preferences.set(.globeDictation, true)
        await settle()
        precondition(configurations == [false] && reserved)
        recorder.active = true
        await settle()
        precondition(configurations == [false, true])
        recorder.active = false
        await settle()
        precondition(configurations == [false, true, false])
        recorder.available = false
        await settle()
        precondition(!reserved && configurations.last == false)
        precondition(enabledConfigurations.last == false)
        recorder.available = true
        await settle()
        precondition(reserved)
        precondition(enabledConfigurations.last == true)
        preferences.set(.globeDictation, false)
        await settle()
        precondition(stops == 1 && !reserved)
        recorder.active = true
        await settle()
        precondition(configurations.count == 5)
        preferences.set(.globeDictation, true)
        await settle()
        precondition(configurations.last == true && reserved)
        module.stop()
        module.stop()
        precondition(stops == 2 && !reserved)
        print("PASS: Globe switch starts/stops engine, reserves Globe, pauses for recording, ignores Island")
    }

    private static func settle() async {
        for _ in 0..<30 { await Task.yield() }
    }
}
