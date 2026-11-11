import Foundation

extension NotchcastFeature.Descriptor {
    static let machRemote = Self(
        title: String(localized: "Remote Mac", table: "Notchcast"),
        subtitle: String(localized: "Connect to the remote Mac using SSH.", table: "Notchcast"),
        group: .system,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
