import Foundation

extension NotchcastFeature.Descriptor {
    static let agentActions = Self(
        title: String(localized: "Agent access", table: "Notchcast"),
        subtitle: String(localized: "Expose actions and read-only state to local agents.", table: "Notchcast"),
        group: .system,
        defaultEnabled: true,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
