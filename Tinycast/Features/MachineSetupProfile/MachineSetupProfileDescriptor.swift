import Foundation

extension NotchcastFeature.Descriptor {
    static let machineSetupProfile = Self(
        title: String(localized: "Machine Setup Profile", table: "Notchcast"),
        subtitle: String(localized: "Plan portable setup imports and exports.", table: "Notchcast"),
        group: .system,
        defaultEnabled: true,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
