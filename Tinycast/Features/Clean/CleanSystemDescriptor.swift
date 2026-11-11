import Foundation

extension NotchcastFeature.Descriptor {
    static let cleanSystem = Self(
        title: String(localized: "System root", table: "Notchcast"),
        subtitle: String(localized: "Runs only when you click an action.", table: "Notchcast"),
        group: .clean,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
