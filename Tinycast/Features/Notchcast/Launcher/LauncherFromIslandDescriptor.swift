import Foundation

extension NotchcastFeature.Descriptor {
    static let launcherFromIsland = Self(
        title: String(localized: "Launcher from Island", table: "Notchcast"),
        subtitle: String(localized: "Open the launcher from the island.", table: "Notchcast"),
        group: .launcher,
        defaultEnabled: true,
        backedUp: true,
        dependencies: [.island],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
