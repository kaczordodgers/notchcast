import Foundation
import Observation

@MainActor
@Observable
final class NotchcastPreferences {
    enum HoverDelay: Double, CaseIterable, Identifiable {
        case short = 0.1, standard = 0.3, medium = 0.5, long = 1
        var id: Double { rawValue }
        var title: String {
            Duration.seconds(rawValue).formatted(.units(
                allowed: [.seconds], width: .abbreviated,
                fractionalPart: .show(length: rawValue < 1 ? 1 : 0)))
        }
    }

    var islandHoverDelay: HoverDelay {
        didSet { defaults.set(islandHoverDelay.rawValue, forKey: "islandHoverDelay") }
    }
    static let shared = NotchcastPreferences(
        suiteName: (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + ".notchcast")

    @ObservationIgnored private let defaults: UserDefaults
    /// Every switch defaults to on, so only the ones turned off are stored.
    private var off: Set<NotchcastFeature>

    init(suiteName: String) {
        let defaults = UserDefaults(suiteName: suiteName)!
        self.defaults = defaults
        islandHoverDelay = HoverDelay(rawValue: defaults.double(forKey: "islandHoverDelay")) ?? .standard
        off = Set(NotchcastFeature.allCases.filter { defaults.object(forKey: $0.rawValue) as? Bool == false })
    }

    func isOn(_ feature: NotchcastFeature) -> Bool { !off.contains(feature) }

    func set(_ feature: NotchcastFeature, _ enabled: Bool) {
        guard isOn(feature) != enabled else { return }
        defaults.set(enabled, forKey: feature.rawValue)
        if enabled { off.remove(feature) } else { off.insert(feature) }
    }
}
