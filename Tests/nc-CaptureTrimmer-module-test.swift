// notchcast-sources: Tinycast/Features/CaptureTrimmer/Service/CaptureTrimmerModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift
// notchcast-sources: Tinycast/Features/CaptureTrimmer/CaptureTrimmerModule+Registration.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastRegistrant.swift

import Foundation

@MainActor final class AppCore {}

@main
struct CaptureTrimmerModuleTest {
    @MainActor static func main() async throws {
        let suite = "trimmer-module-\(UUID())"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let module = CaptureTrimmerModule.shared
        let entries = CaptureTrimmerModule.register(AppCore())
        precondition(entries.count == 1 && entries[0].requires == [.captureTrimmer] && entries[0].requiresAny.isEmpty)
        precondition(entries[0].module === module)
        let controller = NotchcastModuleController(entries, preferences: preferences)
        preferences.set(.captureTrimmer, true)
        controller.run()
        precondition(module.enabled)
        preferences.set(.captureTrimmer, false)
        for _ in 0..<1000 where module.enabled { await Task.yield() }
        precondition(!module.enabled)
        print("PASS: registered module follows its switch")
    }
}
