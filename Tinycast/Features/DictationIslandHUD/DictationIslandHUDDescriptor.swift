import Foundation

extension NotchcastFeature.Descriptor {
    static let dictationIslandHUD = Self(
        title: String(localized: "Dictation in Island", table: "Notchcast"),
        subtitle: String(localized: "Show dictation status in the island.", table: "Notchcast"),
        group: .activities,
        defaultEnabled: true,
        dependencies: [.island],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
