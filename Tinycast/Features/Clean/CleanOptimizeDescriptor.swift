import Foundation

extension NotchcastFeature.Descriptor {
    static let cleanOptimize = Self(
        title: String(localized: "Optimize", table: "Notchcast"),
        subtitle: String(localized: "Runs only when you click an action.", table: "Notchcast"),
        group: .clean,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
