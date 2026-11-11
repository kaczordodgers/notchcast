// notchcast-sources: Tinycast/Features/Tweaks/Model/TweakProfile*.swift
// notchcast-sources: Tinycast/Features/Tweaks/Model/AIOffCatalog.swift Tinycast/Features/Tweaks/Model/PrivacyCatalog.swift
// notchcast-sources: Tinycast/Features/Tweaks/Model/TweakPreference.swift Tinycast/Features/Tweaks/Model/TweakValue.swift
import Foundation
// notchcast-sources: Tinycast/Features/Tweaks/TweakProfileCommands.swift Tests/Support/TweakProfileCommandFakes.swift
// notchcast-sources: Tests/Support/NotchcastPreferencesFake.swift
// notchcast-kit: command

@main
struct AICommandTests {
    @MainActor
    static func main() async throws {
        TweakProfileCommands.ai.run()
        for _ in 0..<1000 where TweaksModule.shared.calls == 0 { await Task.yield() }
        precondition(TweaksModule.shared.calls == 1 && TweaksModule.shared.kept == [])
        var calls = 0
        func request(_ kept: Set<String>?, _ privacy: Set<String>) async throws {
            precondition(kept == [] && privacy.isEmpty)
            let data = try TweakProfile.data(bundleIdentifier: "test", keepingAI: kept, privacy: privacy)
            precondition(!data.isEmpty)
            calls += 1
        }
        try await TweakProfileCommandRunner.run(ai: true, enabled: { true }, confirm: { true }, request: request)
        precondition(calls == 1)
        try await TweakProfileCommandRunner.run(ai: true, enabled: { true }, confirm: { false }, request: request)
        try await TweakProfileCommandRunner.run(ai: true, enabled: { false }, confirm: { true }, request: request)
        var enabled = true
        try await TweakProfileCommandRunner.run(ai: true, enabled: { enabled }, confirm: {
            enabled = false
            return true
        }, request: request)
        precondition(calls == 1)
        print("PASS: AI command reaches profile engine; decline, disabled and stale confirmation have no effects")
    }
}
