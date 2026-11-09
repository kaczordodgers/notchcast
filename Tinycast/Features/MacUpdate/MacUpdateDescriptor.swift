import Foundation

extension NotchcastFeature.Descriptor {
    static let macUpdate = Self(
        title: String(localized: "Update this Mac", table: "Notchcast"),
        subtitle: String(localized: "Run maintenance only after confirmation.", table: "Notchcast"),
        group: .tools,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: true,
        isSystemTweak: false
    )
}
