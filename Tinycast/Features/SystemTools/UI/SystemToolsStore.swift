import Foundation

@MainActor
final class SystemToolsStore {
    private let preferences: NotchcastPreferences
    private let available: (NotchcastFeature) -> Bool
    private let apply: (NotchcastFeature, Bool) throws -> Void

    init(preferences: NotchcastPreferences,
         available: @escaping (NotchcastFeature) -> Bool,
         apply: @escaping (NotchcastFeature, Bool) throws -> Void) {
        self.preferences = preferences
        self.available = available
        self.apply = apply
    }

    func set(_ feature: NotchcastFeature, enabled: Bool) throws {
        guard feature.isSystemTweak, available(feature), preferences.isOn(feature) != enabled else { return }
        try apply(feature, enabled)
        preferences.set(feature, enabled)
    }
}
