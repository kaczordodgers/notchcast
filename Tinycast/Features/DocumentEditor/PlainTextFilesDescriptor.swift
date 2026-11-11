import Foundation

extension NotchcastFeature.Descriptor {
    static let plainTextFiles = Self(
        title: String(localized: "Plain Text Files", table: "Notchcast"),
        subtitle: String(localized: "Edit plain text while preserving its file encoding.", table: "Notchcast"),
        group: .system,
        defaultEnabled: true,
        backedUp: true,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
