import Foundation
import Observation

@MainActor
@Observable
final class EditorPreferences {
    enum FontPreset: String, Sendable { case system, jetBrainsMono }
    enum ThemePreset: String, Sendable { case system, githubDark }

    var font: FontPreset { didSet { defaults.set(font.rawValue, forKey: "font") } }
    var theme: ThemePreset { didSet { defaults.set(theme.rawValue, forKey: "theme") } }
    var pairsAutomatically: Bool { didSet { defaults.set(pairsAutomatically, forKey: "pairsAutomatically") } }
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        font = defaults.string(forKey: "font").flatMap(FontPreset.init(rawValue:)) ?? .jetBrainsMono
        theme = defaults.string(forKey: "theme").flatMap(ThemePreset.init(rawValue:)) ?? .githubDark
        pairsAutomatically = defaults.object(forKey: "pairsAutomatically") as? Bool ?? true
    }
}
