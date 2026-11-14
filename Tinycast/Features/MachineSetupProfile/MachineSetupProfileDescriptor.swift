import Foundation

extension NotchcastFeature.Descriptor {
    static let machineSetupProfile = Self(
        title: String(localized: "Machine Setup Profile", table: "Notchcast"),
        subtitle: String(localized: "Preview and apply supported setup tweaks from a profile.", table: "Notchcast"),
        group: .system,
        defaultEnabled: true,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
