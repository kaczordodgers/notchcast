/// One switch for every feature, or `only` the listed ones, for harnesses that declare their own NotchcastFeature.
@MainActor
final class NotchcastPreferences {
    static let shared = NotchcastPreferences()
    var enabled = true
    var only: Set<NotchcastFeature>?
    func isOn(_ feature: NotchcastFeature) -> Bool { only?.contains(feature) ?? enabled }
}
