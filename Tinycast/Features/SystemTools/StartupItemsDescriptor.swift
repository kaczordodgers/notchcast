import Foundation

extension NotchcastFeature.Descriptor {
    static let startupItems = Self(
        title: String(localized: "Startup Items", table: "Notchcast"),
        subtitle: String(localized: "Manage user LaunchAgents and inspect system items.", table: "Notchcast"),
        group: .tweaks,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: true,
        usesSystemToolsHelper: true
    )
}
