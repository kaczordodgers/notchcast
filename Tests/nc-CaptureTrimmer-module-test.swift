// notchcast-sources: Tinycast/Features/CaptureTrimmer/Service/CaptureTrimmerModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift

import Foundation

@main
struct CaptureTrimmerModuleTest {
    @MainActor static func main() async throws {
        let suite = "trimmer-module-\(UUID())"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let module = CaptureTrimmerModule.live()
        let controller = NotchcastModuleController([
            .init(requires: [.captureTrimmer], module: module)], preferences: preferences)
        preferences.set(.captureTrimmer, true)
        controller.run()
        precondition(module.enabled)
        preferences.set(.captureTrimmer, false)
        for _ in 0..<1000 where module.enabled { await Task.yield() }
        precondition(!module.enabled)
        print("PASS: module follows its switch")
    }
}
