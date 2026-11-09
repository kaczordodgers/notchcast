import Foundation

extension NotchcastFeature.Descriptor {
    static let agentConfirmation = Self(
        title: String(localized: "Agent Confirmation", table: "Notchcast"),
        subtitle: String(localized: "Ask before allowing agent requests.", table: "Notchcast"),
        group: .islandOptions,
        defaultEnabled: true,
        dependencies: [.island],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
