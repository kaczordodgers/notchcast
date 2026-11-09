import Foundation

extension NotchcastFeature.Descriptor {
    static let agentAnswer = Self(
        title: String(localized: "Agent Answers", table: "Notchcast"),
        subtitle: String(localized: "Reply to waiting agents.", table: "Notchcast"),
        group: .captureAndDictation,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
