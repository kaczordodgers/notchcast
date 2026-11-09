import Foundation

extension NotchcastFeature.Descriptor {
    static let downloadsAria2 = Self(
        title: String(localized: "Fast Downloads with aria2c", table: "Notchcast"),
        subtitle: String(localized: "Use aria2c for faster media downloads when it is installed.", table: "Notchcast"),
        group: .activities,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
