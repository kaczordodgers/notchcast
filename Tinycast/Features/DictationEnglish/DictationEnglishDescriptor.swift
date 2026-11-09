import Foundation

extension NotchcastFeature.Descriptor {
    static let dictationEnglish = Self(
        title: String(localized: "Dictate in English", table: "Notchcast"),
        subtitle: String(localized: "Use English for dictation.", table: "Notchcast"),
        group: .captureAndDictation,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [.accessibility],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
