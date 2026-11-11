import Foundation

extension NotchcastFeature.Descriptor {
    static let openBotAgents = Self(
        title: String(localized: "OpenBot Agents", table: "Notchcast"),
        subtitle: String(localized: "Read waiting items from local OpenBot agents.", table: "Notchcast"),
        group: .activities,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
