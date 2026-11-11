/// One switch for every feature, for harnesses that declare their own NotchcastFeature instead of the core kit.
@MainActor
final class NotchcastPreferences {
    static let shared = NotchcastPreferences()
    var enabled = true
    func isOn(_ feature: NotchcastFeature) -> Bool { enabled }
}
