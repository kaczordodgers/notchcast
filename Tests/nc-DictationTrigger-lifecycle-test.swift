// notchcast-sources: -swift-version 6 -strict-concurrency=complete
// notchcast-sources: Tinycast/Features/Notchcast/Core/Notchcast[FMP]*.swift
// notchcast-sources: Tinycast/Features/DictationTrigger/DictationTriggerModule.swift
import Foundation
import Observation

@MainActor @Observable
private final class Recorder { var active = false }

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
        var stops = 0
        let module = DictationTriggerModule(
            paused: { recorder.active }, reserve: { reserved = $0 },
            configure: { enabled, paused in
                precondition(enabled)
                configurations.append(paused)
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
        preferences.set(.globeDictation, false)
        await settle()
        precondition(stops == 1 && !reserved)
        recorder.active = true
        await settle()
        precondition(configurations.count == 3)
        preferences.set(.globeDictation, true)
        await settle()
        precondition(configurations.last == true && reserved)
        module.stop()
        module.stop()
        precondition(stops == 2 && !reserved)
        precondition(!NotchcastFeature.globeDictation.needsIsland)
        precondition(NotchcastFeature.globeDictation.requiredGrants == [.accessibility])
        print("PASS: Globe switch starts/stops engine, reserves Globe, pauses for recording, ignores Island")
    }

    private static func settle() async {
        for _ in 0..<30 { await Task.yield() }
    }
}
