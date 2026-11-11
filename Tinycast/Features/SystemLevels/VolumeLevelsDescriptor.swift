import Foundation

extension NotchcastFeature.Descriptor {
    static let volumeLevels = Self(
        title: String(localized: "Volume in Island", table: "Notchcast"),
        subtitle: String(localized: "Replaces the macOS volume overlay.", table: "Notchcast"),
        group: .system,
        defaultEnabled: true,
        backedUp: true,
        dependencies: [.island],
        requiredGrants: [.accessibility],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
