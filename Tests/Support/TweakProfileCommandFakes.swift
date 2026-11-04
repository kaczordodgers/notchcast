import Foundation

enum NotchcastFeature: Sendable {
    case aiFeaturesOff
    case privacyChoices
    var title: String { "fixture" }
}

@MainActor
final class NotchcastPreferences {
    static let shared = NotchcastPreferences()
    func isOn(_ feature: NotchcastFeature) -> Bool { true }
}

struct NotchcastCommand: Sendable {
    let slug: String
    let name: String
    let sfSymbol: String
    var feature: NotchcastFeature?
    var isEnabled: @MainActor @Sendable () -> Bool = { true }
    let run: @MainActor @Sendable () -> Void
}

@MainActor
final class AppCore {
    static let shared = AppCore()
    func confirm(title: String, message: String, symbol: String, confirmTitle: String) async -> Bool { true }
    func showMessage(_ message: String) { fatalError(message) }
}

@MainActor
enum NotchcastCore {
    static let tweaks = FakeTweaks()
}

@MainActor
final class FakeTweaks {
    var calls = 0
    var kept: Set<String>?
    var privacy: Set<String> = []
    func requestProfile(keepingAI: Set<String>?, privacy: Set<String>) async throws -> URL {
        let data = try TweakProfile.data(bundleIdentifier: "test", keepingAI: keepingAI, privacy: privacy)
        precondition(!data.isEmpty)
        kept = keepingAI
        self.privacy = privacy
        calls += 1
        return URL(fileURLWithPath: "/fixture.mobileconfig")
    }
}
