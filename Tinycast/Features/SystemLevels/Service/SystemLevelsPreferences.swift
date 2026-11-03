import Foundation
import Observation

@MainActor @Observable
final class SystemLevelsPreferences {
    var microphone: Bool { didSet { defaults.set(microphone, forKey: "notchcast.levels.microphone") } }
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = UserDefaults(suiteName:
         (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + ".notchcast")!) {
        self.defaults = defaults
        microphone = defaults.object(forKey: "notchcast.levels.microphone") as? Bool ?? true
    }
}
