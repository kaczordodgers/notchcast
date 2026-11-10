// notchcast-sources: Tinycast/Features/Tweaks/Model/TweakProfile*.swift
// notchcast-sources: Tinycast/Features/Tweaks/Model/AIOffCatalog.swift Tinycast/Features/Tweaks/Model/PrivacyCatalog.swift
// notchcast-sources: Tinycast/Features/Tweaks/Model/TweakPreference.swift Tinycast/Features/Tweaks/Model/TweakValue.swift
import Foundation
// notchcast-sources: Tinycast/Features/Tweaks/TweakProfileCommands.swift Tests/Support/TweakProfileCommandFakes.swift

@main
struct PrivacyCommandTests {
    @MainActor
    static func main() async throws {
        TweakProfileCommands.privacy.run()
        for _ in 0..<1000 where TweaksModule.shared.calls == 0 { await Task.yield() }
        precondition(TweaksModule.shared.calls == 1 && TweaksModule.shared.kept == nil)
        var calls = 0
        func request(_ kept: Set<String>?, _ privacy: Set<String>) async throws {
            precondition(kept == nil)
            precondition(privacy == Set(PrivacyCatalog.restrictions.keys).union(PrivacyCatalog.preferences.keys))
            let data = try TweakProfile.data(bundleIdentifier: "test", keepingAI: kept, privacy: privacy)
            precondition(!data.isEmpty)
            calls += 1
        }
        try await TweakProfileCommandRunner.run(ai: false, enabled: { true }, confirm: { true }, request: request)
        precondition(calls == 1)
        try await TweakProfileCommandRunner.run(ai: false, enabled: { true }, confirm: { false }, request: request)
        try await TweakProfileCommandRunner.run(ai: false, enabled: { false }, confirm: { true }, request: request)
        precondition(calls == 1)
        print("PASS: privacy command reaches profile engine; declined and disabled commands have no effects")
    }
}
