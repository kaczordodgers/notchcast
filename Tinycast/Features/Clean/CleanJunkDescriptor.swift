import Foundation

extension NotchcastFeature.Descriptor {
    static let cleanJunk = Self(
        title: String(localized: "Junk", table: "Notchcast"),
        subtitle: String(localized: "Runs only when you click an action.", table: "Notchcast"),
        group: .clean,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
