import Foundation

extension NotchcastFeature.Descriptor {
    static let distill = Self(
        title: String(localized: "Distill", table: "Notchcast"),
        subtitle: String(localized: "Save links and transcribe media into your Distill folder.", table: "Notchcast"),
        group: .activities,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
