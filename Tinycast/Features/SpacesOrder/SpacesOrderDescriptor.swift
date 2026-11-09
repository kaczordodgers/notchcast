import Foundation

extension NotchcastFeature.Descriptor {
    static let spacesOrder = Self(
        title: String(localized: "Keep Spaces in a fixed order", table: "Notchcast"),
        subtitle: String(localized: "Prevent automatic Spaces reordering and restore your setting when turned off.", table: "Notchcast"),
        group: .system,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
