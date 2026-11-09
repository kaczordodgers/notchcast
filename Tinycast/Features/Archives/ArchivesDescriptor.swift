import Foundation

extension NotchcastFeature.Descriptor {
    static let archives = Self(
        title: String(localized: "Archives"),
        subtitle: String(localized: "Extract opened archives beside the original file.", table: "Notchcast"),
        group: .archives,
        defaultEnabled: true,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
