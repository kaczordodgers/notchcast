import Foundation

extension NotchcastFeature.Descriptor {
    static let island = Self(
        title: String(localized: "Island", table: "Notchcast"),
        subtitle: String(localized: "Show the island at the top of the screen.", table: "Notchcast"),
        group: .island,
        defaultEnabled: true,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
