import Foundation
import Observation

@MainActor
@Observable
final class NotchcastPreferences {
    static let shared = NotchcastPreferences(
        suiteName: (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + ".notchcast")

    @ObservationIgnored private let defaults: UserDefaults
    /// Every switch defaults to on, so only the ones turned off are stored.
    private var off: Set<NotchcastFeature>

    init(suiteName: String) {
        let defaults = UserDefaults(suiteName: suiteName)!
        self.defaults = defaults
        off = Set(NotchcastFeature.allCases.filter { defaults.object(forKey: $0.rawValue) as? Bool == false })
    }

    func isOn(_ feature: NotchcastFeature) -> Bool { !off.contains(feature) }

    func set(_ feature: NotchcastFeature, _ enabled: Bool) {
        guard isOn(feature) != enabled else { return }
        defaults.set(enabled, forKey: feature.rawValue)
        if enabled { off.remove(feature) } else { off.insert(feature) }
    }
}
