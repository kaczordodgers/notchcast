import Foundation

extension NotchcastFeature.Descriptor {
    static let globeDictation = Self(
        title: String(localized: "Globe Dictation", table: "Notchcast"),
        subtitle: String(localized: "Tap Globe to start or finish dictation, or hold it to talk.", table: "Notchcast"),
        group: .captureAndDictation,
        defaultEnabled: true,
        dependencies: [],
        requiredGrants: [.accessibility, .microphone],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
