import Foundation

@MainActor
final class SystemToolsStore {
    private let preferences: NotchcastPreferences
    private let available: (NotchcastFeature) -> Bool
    private let apply: (NotchcastFeature, Bool) async throws -> Void

    init(preferences: NotchcastPreferences,
         available: @escaping (NotchcastFeature) -> Bool,
         apply: @escaping (NotchcastFeature, Bool) async throws -> Void) {
        self.preferences = preferences
        self.available = available
        self.apply = apply
    }

    func set(_ feature: NotchcastFeature, enabled: Bool) async throws {
        guard feature.isSystemTweak, available(feature), preferences.isOn(feature) != enabled else { return }
        try await apply(feature, enabled)
        preferences.set(feature, enabled)
    }
}
