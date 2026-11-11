// notchcast-sources: -swift-version 6 -strict-concurrency=complete
// notchcast-kit: core
// notchcast-sources: Tinycast/Features/DictationCleanup/DictationCleanupModule.swift
// notchcast-sources: Tinycast/Features/DictationCleanup/Model/DictationCleanupSettings.swift
// notchcast-sources: Tinycast/Features/DictationCleanup/Service/DictationCleanupSettingsStore.swift
import Foundation

@main
struct CleanupLifecycleTest {
    @MainActor
    static func main() async throws {
        let terms = DictationCleanupSettings.vocabulary(from: " Tudu | tu | d \nName|")
        precondition(terms[0] == .init(spelling: "Tudu", misheardForms: ["tu", "d"]))
        precondition(terms[1] == .init(spelling: "Name", misheardForms: [""]))
        let suite = "cleanup-lifecycle-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let store = DictationCleanupSettingsStore(defaults: defaults, bundleIdentifier: suite)
        let unreadable = DictationCleanupModule(store: store, install: {}, uninstall: {}, readAPIKey: {
            throw DictationCleanupSettingsStore.Failure.invalidKey
        })
        var failures = 0
        unreadable.reportFailure = { failures += 1 }
        precondition(unreadable.apiKey() == nil && failures == 1)
        let absent = DictationCleanupModule(store: store, install: {}, uninstall: {}, readAPIKey: { nil })
        precondition(absent.apiKey() == "")
        var installed = false
        var starts = 0
        let module = DictationCleanupModule(store: store, install: {
            installed = true
            starts += 1
        }, uninstall: { installed = false })
        module.load()
        let controller = NotchcastModuleController([
            .init(requires: [.dictationCleanup], module: module)
        ], preferences: preferences)
        controller.run()
        precondition(!installed && !preferences.isOn(.dictationCleanup))
        preferences.set(.dictationCleanup, true)
        for _ in 0..<20 { await Task.yield() }
        precondition(installed && starts == 1)
        let enabled = try store.read()
        precondition(enabled.isEnabled)
        preferences.set(.island, false)
        for _ in 0..<20 { await Task.yield() }
        precondition(installed && starts == 1)
        preferences.set(.dictationCleanup, false)
        for _ in 0..<20 { await Task.yield() }
        precondition(!installed)
        let saved = try store.read()
        precondition(!saved.isEnabled)
        var updated = saved
        updated.promptAddition = "Preserve names"
        precondition(module.save(updated))
        let restored = try store.read()
        precondition(restored == updated)
        print("PASS: cleanup defaults off, installs/removes stage, persists settings and ignores Island")
    }
}
