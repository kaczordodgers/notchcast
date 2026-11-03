import Foundation
import Observation

@MainActor
@Observable
final class NotchcastPreferences {
    static let shared = NotchcastPreferences(
        suiteName: (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + ".notchcast")

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onChange: ((NotchcastFeature) -> Void)?
    private var switches: [NotchcastFeature: Bool]

    init(suiteName: String) {
        let defaults = UserDefaults(suiteName: suiteName)!
        self.defaults = defaults
        switches = Dictionary(uniqueKeysWithValues: NotchcastFeature.allCases.map {
            ($0, defaults.object(forKey: $0.rawValue) as? Bool ?? true)
        })
    }

    func isOn(_ feature: NotchcastFeature) -> Bool { switches[feature] ?? true }

    func set(_ feature: NotchcastFeature, _ enabled: Bool) {
        guard isOn(feature) != enabled else { return }
        defaults.set(enabled, forKey: feature.rawValue)
        switches[feature] = enabled
        onChange?(feature)
    }
}
