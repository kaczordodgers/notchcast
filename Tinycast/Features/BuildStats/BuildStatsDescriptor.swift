import Foundation

extension NotchcastFeature.Descriptor {
    static let buildStats = Self(
        title: String(localized: "Build statistics", table: "Notchcast"),
        subtitle: String(localized: "Read a local build snapshot.", table: "Notchcast"),
        group: .buildStats,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
