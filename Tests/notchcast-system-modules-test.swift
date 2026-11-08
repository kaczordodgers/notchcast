// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Model/*.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityPreferences.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityStore.swift
// notchcast-sources: Tinycast/Features/SystemTools/Model/*.swift Tinycast/Features/SystemTools/Service/*.swift
// notchcast-sources: Tinycast/Features/SystemTools/UI/*.swift
// notchcast-sources: Tinycast/Features/Tweaks/Model/*.swift Tinycast/Features/Tweaks/Service/*.swift
// notchcast-sources: Tinycast/Features/Tweaks/TweaksModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Root/*.swift Tinycast/Platform/ProcessExit.swift
import Foundation

@MainActor
final class AppCore {
    enum Tone { case success, danger }
    func confirm(title: String, message: String, symbol: String, confirmTitle: String) async -> Bool { false }
    func showMessage(_ message: String, tone: Tone = .success) { preconditionFailure(message) }
}

@main
struct SystemModuleTests {
    @MainActor
    static func main() async throws {
        let suite = "app.notchcast.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let journalDefaults = UserDefaults(suiteName:
            (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + ".notchcast")!
        let journalKey = UUID().uuidString
        defer { journalDefaults.removeObject(forKey: journalKey) }
        let plan = TypingPreferencePlan(entries: [])
        let encoded = try JSONEncoder().encode(plan)
        let entry = try JSONSerialization.jsonObject(with: encoded)
        journalDefaults.set(try JSONSerialization.data(withJSONObject:
            ["valid": entry, "malformed": ["entries": "invalid"], "scalar": 7]), forKey: journalKey)
        let recovered = TweaksModule(key: journalKey)
        precondition(recovered.store.plans == ["valid": plan])
        let saved = try JSONDecoder().decode([String: TypingPreferencePlan].self,
            from: journalDefaults.data(forKey: journalKey)!)
        precondition(saved == ["valid": plan])
        let retired = TypingPreferencePlan(entries: [.init(
            write: .init("com.apple.dock", "mru-spaces", .bool(false)), previous: .bool(true))])
        journalDefaults.set(try JSONEncoder().encode(["spaces-fixed": retired]), forKey: journalKey)
        precondition(TweaksModule(key: journalKey).store.plans.isEmpty)
        let malformed = try JSONSerialization.data(withJSONObject: ["bad": 7])
        journalDefaults.set(malformed, forKey: journalKey)
        precondition(TweaksModule(key: journalKey).store.plans.isEmpty)
        precondition(journalDefaults.data(forKey: journalKey) == malformed)
        let corrupt = Data("not JSON".utf8)
        journalDefaults.set(corrupt, forKey: journalKey)
        let unreadable = TweaksModule(key: journalKey)
        unreadable.store.start()
        do {
            try await unreadable.store.set("new", writes: [], on: true)
            preconditionFailure("An unreadable journal must block replacement")
        } catch SystemToolsProcessRunner.Failure.invalidExecutable {}
        precondition(journalDefaults.data(forKey: journalKey) == corrupt)
        var effects: [Bool] = []
        let store = SystemToolsStore(preferences: preferences, available: { _ in true }, apply: { _, value in
            effects.append(value)
        })
        try await store.set(.sudoTouchID, enabled: true)
        try await store.set(.sudoTouchID, enabled: false)
        precondition(effects == [true, false])
        let module = TweaksModule(key: UUID().uuidString)
        let controller = NotchcastModuleController([
            .init(requires: [], requiresAny: [.macSetup, .privacyChoices], module: module)
        ], preferences: preferences)
        controller.run()
        precondition(!module.running)
        preferences.set(.macSetup, true)
        for _ in 0..<20 { await Task.yield() }
        precondition(module.running)
        preferences.set(.macSetup, false)
        for _ in 0..<20 { await Task.yield() }
        precondition(!module.running)
        print("Module switch lifecycle and asynchronous store reversal passed with fake effects")
    }
}
