import Foundation

extension NotchcastFeature.Descriptor {
    static let voiceAsk = Self(
        title: String(localized: "Voice Ask", table: "Notchcast"),
        subtitle: String(localized: "Voice Ask destination", table: "Notchcast"),
        group: .captureAndDictation,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [.accessibility, .microphone],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
