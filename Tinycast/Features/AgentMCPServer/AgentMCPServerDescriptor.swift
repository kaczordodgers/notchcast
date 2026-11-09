import Foundation

extension NotchcastFeature.Descriptor {
    static let agentMCPServer = Self(
        title: String(localized: "Agent MCP Server", table: "Notchcast"),
        subtitle: String(localized: "Nothing is exposed until the CLI is available.", table: "Notchcast"),
        group: .captureAndDictation,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
