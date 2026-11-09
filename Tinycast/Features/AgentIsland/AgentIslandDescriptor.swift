import Foundation

extension NotchcastFeature.Descriptor {
    static let agentIsland = Self(
        title: String(localized: "Agent Island", table: "Notchcast"),
        subtitle: String(localized: "Summarize waiting and working agents.", table: "Notchcast"),
        group: .activities,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
