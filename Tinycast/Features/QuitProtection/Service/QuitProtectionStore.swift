import Foundation
import Observation

@MainActor @Observable
final class QuitProtectionStore {
    @ObservationIgnored private let defaults: UserDefaults
    private let key = "notchcast.quitProtection."

    init(defaults: UserDefaults = NotchcastIdentity.current.defaults) {
        self.defaults = defaults
        configuration = .init(
            quitEnabled: defaults.object(forKey: key + "quitEnabled") as? Bool ?? true,
            closeEnabled: defaults.bool(forKey: key + "closeEnabled"),
            mode: defaults.string(forKey: key + "mode").flatMap(QuitProtectionEngine.Mode.init) ?? .hold,
            exceptions: Set(defaults.stringArray(forKey: key + "exceptions") ?? []))
    }

    var configuration: QuitProtectionEngine.Configuration {
        didSet {
            defaults.set(configuration.quitEnabled, forKey: key + "quitEnabled")
            defaults.set(configuration.closeEnabled, forKey: key + "closeEnabled")
            defaults.set(configuration.mode.rawValue, forKey: key + "mode")
            defaults.set(configuration.exceptions.sorted(), forKey: key + "exceptions")
        }
    }
}
