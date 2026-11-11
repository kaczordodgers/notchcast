import Foundation

extension NotchcastFeature.Descriptor {
    static let agentCLI = Self(
        title: String(localized: "Command line tool", table: "Notchcast"),
        subtitle: String(localized: "Accept local commands over a private Unix socket.", table: "Notchcast"),
        group: .system,
        defaultEnabled: true,
        backedUp: false,
        dependencies: [.agentActions],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
