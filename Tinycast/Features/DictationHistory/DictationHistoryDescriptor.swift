import Foundation

extension NotchcastFeature.Descriptor {
    static let dictationHistory = Self(
        title: String(localized: "Keep dictation history", table: "Notchcast"),
        subtitle: String(localized: "Save transcripts for later review.", table: "Notchcast"),
        group: .captureAndDictation,
        defaultEnabled: true,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
