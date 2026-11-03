import Foundation

@MainActor
final class QuitProtectionStore {
    private let defaults: UserDefaults
    private let key = "notchcast.quitProtection."

    init(defaults: UserDefaults = UserDefaults(suiteName:
             (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + ".notchcast")!) {
        self.defaults = defaults
    }

    var configuration: QuitProtectionEngine.Configuration {
        get {
            .init(quitEnabled: defaults.object(forKey: key + "quitEnabled") as? Bool ?? true,
                  closeEnabled: defaults.bool(forKey: key + "closeEnabled"),
                  mode: defaults.string(forKey: key + "mode").flatMap(QuitProtectionEngine.Mode.init) ?? .hold,
                  exceptions: Set(defaults.stringArray(forKey: key + "exceptions") ?? []))
        }
        set {
            defaults.set(newValue.quitEnabled, forKey: key + "quitEnabled")
            defaults.set(newValue.closeEnabled, forKey: key + "closeEnabled")
            defaults.set(newValue.mode.rawValue, forKey: key + "mode")
            defaults.set(newValue.exceptions.sorted(), forKey: key + "exceptions")
        }
    }
}
