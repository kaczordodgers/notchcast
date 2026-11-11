import Foundation
import Observation

@MainActor @Observable
final class QuitProtectionStore {
    nonisolated static let quitEnabledKey = "notchcast.quitProtection.quitEnabled"
    nonisolated static let closeEnabledKey = "notchcast.quitProtection.closeEnabled"
    nonisolated static let modeKey = "notchcast.quitProtection.mode"
    nonisolated static let exceptionsKey = "notchcast.quitProtection.exceptions"
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = NotchcastIdentity.current.defaults) {
        self.defaults = defaults
        configuration = .init(
            quitEnabled: defaults.object(forKey: Self.quitEnabledKey) as? Bool ?? true,
            closeEnabled: defaults.bool(forKey: Self.closeEnabledKey),
            mode: defaults.string(forKey: Self.modeKey).flatMap(QuitProtectionEngine.Mode.init) ?? .hold,
            exceptions: Set(defaults.stringArray(forKey: Self.exceptionsKey) ?? []))
    }

    var configuration: QuitProtectionEngine.Configuration {
        didSet {
            defaults.set(configuration.quitEnabled, forKey: Self.quitEnabledKey)
            defaults.set(configuration.closeEnabled, forKey: Self.closeEnabledKey)
            defaults.set(configuration.mode.rawValue, forKey: Self.modeKey)
            defaults.set(configuration.exceptions.sorted(), forKey: Self.exceptionsKey)
        }
    }
}
