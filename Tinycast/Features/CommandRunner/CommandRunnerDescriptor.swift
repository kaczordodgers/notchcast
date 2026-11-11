import Foundation

extension NotchcastFeature.Descriptor {
    static let commandRunner = Self(
        title: String(localized: "Command Runner", table: "Notchcast"),
        subtitle: String(localized: "Run commands from a host profile.", table: "Notchcast"),
        group: .launcher,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
