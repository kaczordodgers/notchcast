import Foundation

extension NotchcastFeature.Descriptor {
    static let agentSessions = Self(
        title: String(localized: "Agent Session Logs", table: "Notchcast"),
        subtitle: String(localized: "Read local agent session metadata and token usage on demand.", table: "Notchcast"),
        group: .activities,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
