import Foundation

extension NotchcastFeature.Descriptor {
    static let appUpdates = Self(
        title: String(localized: "App updates", table: "Notchcast"),
        subtitle: String(localized: "Check installed apps for updates on demand.", table: "Notchcast"),
        group: .tools,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: true,
        isSystemTweak: false
    )
}
