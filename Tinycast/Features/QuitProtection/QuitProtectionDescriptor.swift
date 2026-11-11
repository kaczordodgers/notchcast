import Foundation

extension NotchcastFeature.Descriptor {
    static let quitProtection = Self(
        title: String(localized: "Quit Protection", table: "Notchcast"),
        subtitle: String(localized: "Stops an app from quitting on a single slip.", table: "Notchcast"),
        group: .system,
        defaultEnabled: true,
        backedUp: true,
        dependencies: [],
        requiredGrants: [.accessibility],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
