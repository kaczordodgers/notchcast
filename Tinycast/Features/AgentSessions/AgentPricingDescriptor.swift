import Foundation

extension NotchcastFeature.Descriptor {
    static let agentPricing = Self(
        title: String(localized: "Agent API Value", table: "Notchcast"),
        subtitle: String(localized: "Estimate API value from local agent token usage.", table: "Notchcast"),
        group: .agentPricing,
        defaultEnabled: false,
        backedUp: true,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
