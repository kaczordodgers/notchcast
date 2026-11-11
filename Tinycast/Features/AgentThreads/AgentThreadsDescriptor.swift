import Foundation

extension NotchcastFeature.Descriptor {
    static let agentThreads = Self(
        title: String(localized: "Agent Threads", table: "Notchcast"),
        subtitle: String(localized: "Read active and recently finished agent threads on this Mac.", table: "Notchcast"),
        group: .activities,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
