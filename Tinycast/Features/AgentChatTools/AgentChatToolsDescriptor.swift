import Foundation

extension NotchcastFeature.Descriptor {
    static let agentChatTools = Self(
        title: String(localized: "AI Chat Tools", table: "Notchcast"),
        subtitle: String(localized: "Add Notchcast tools to AI chat.", table: "Notchcast"),
        group: .captureAndDictation,
        defaultEnabled: true,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
