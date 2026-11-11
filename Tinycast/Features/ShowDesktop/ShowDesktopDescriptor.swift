import Foundation

extension NotchcastFeature.Descriptor {
    static let showDesktop = Self(
        title: String(localized: "Show Desktop with F3", table: "Notchcast"),
        subtitle: String(localized: "Press F3 to show the desktop; press again to restore windows.", table: "Notchcast"),
        group: .system,
        defaultEnabled: true,
        backedUp: true,
        dependencies: [],
        requiredGrants: [.accessibility],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
