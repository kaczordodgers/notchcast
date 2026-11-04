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
    enum Tone { case danger }
    func confirm(title: String, message: String, symbol: String, confirmTitle: String) async -> Bool { false }
    func showMessage(_ message: String, tone: Tone) { preconditionFailure(message) }
}

@main
struct SystemModuleTests {
    @MainActor
    static func main() async throws {
        let suite = "app.notchcast.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        var effects: [Bool] = []
        let store = SystemToolsStore(preferences: preferences, available: { _ in true }, apply: { _, value in
            effects.append(value)
        })
        try await store.set(.sudoTouchID, enabled: true)
        try await store.set(.sudoTouchID, enabled: false)
        precondition(effects == [true, false])
        let module = TweaksModule()
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
