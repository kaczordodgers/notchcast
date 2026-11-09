import Foundation

extension NotchcastFeature.Descriptor {
    static let updateRemote = Self(
        title: String(localized: "Update Remote Mac", table: "Notchcast"),
        subtitle: String(localized: "Run the update on the remote Mac.", table: "Notchcast"),
        group: .system,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
