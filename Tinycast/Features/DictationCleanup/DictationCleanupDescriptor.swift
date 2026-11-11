import Foundation

extension NotchcastFeature.Descriptor {
    static let dictationCleanup = Self(
        title: String(localized: "AI cleanup", table: "Notchcast"),
        subtitle: String(localized: "Clean up final dictation transcripts.", table: "Notchcast"),
        group: .captureAndDictation,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
