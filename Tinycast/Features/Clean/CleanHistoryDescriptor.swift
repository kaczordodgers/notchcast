import Foundation

extension NotchcastFeature.Descriptor {
    static let cleanHistory = Self(
        title: String(localized: "Clean history", table: "Notchcast"),
        subtitle: String(localized: "Runs only when you click an action.", table: "Notchcast"),
        group: .clean,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
