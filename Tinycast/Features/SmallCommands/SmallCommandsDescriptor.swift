import Foundation

extension NotchcastFeature.Descriptor {
    static let smallCommands = Self(
        title: String(localized: "Small Commands", table: "Notchcast"),
        subtitle: String(localized: "Passwords, short links, noise control and AirDrop. Noise control requires English system language.", table: "Notchcast"),
        group: .launcher,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [.accessibility],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
