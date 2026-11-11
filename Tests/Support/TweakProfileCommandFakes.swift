import Foundation

enum NotchcastFeature: Sendable {
    case aiFeaturesOff
    case privacyChoices
    var title: String { "fixture" }
}

@MainActor
final class AppCore {
    static let shared = AppCore()
    func confirm(title: String, message: String, symbol: String, confirmTitle: String) async -> Bool { true }
    func showMessage(_ message: String) { fatalError(message) }
}

@MainActor
final class TweaksModule {
    static let shared = TweaksModule()
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
