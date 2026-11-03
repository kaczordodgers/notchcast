import Foundation
import Observation

@MainActor
@Observable
final class NotchcastPreferences {
    static let shared = NotchcastPreferences(
        suiteName: (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + ".notchcast")

    @ObservationIgnored private let defaults: UserDefaults
    private var off: Set<NotchcastFeature>

    init(suiteName: String) {
        let defaults = UserDefaults(suiteName: suiteName)!
        self.defaults = defaults
        off = Set(NotchcastFeature.allCases.filter {
            !(defaults.object(forKey: $0.rawValue) as? Bool ?? $0.defaultOn)
        })
    }

    func isOn(_ feature: NotchcastFeature) -> Bool { !off.contains(feature) }
    func isEnabled(_ feature: NotchcastFeature) -> Bool {
        isOn(feature) && feature.dependencies.allSatisfy(isEnabled)
    }

    var engineDefaults: UserDefaults { defaults }

    func set(_ feature: NotchcastFeature, _ enabled: Bool) {
        guard isOn(feature) != enabled else { return }
        defaults.set(enabled, forKey: feature.rawValue)
        if enabled { off.remove(feature) } else { off.insert(feature) }
    }
}
