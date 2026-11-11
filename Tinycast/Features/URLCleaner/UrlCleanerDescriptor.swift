import Foundation

extension NotchcastFeature.Descriptor {
    static let urlCleaner = Self(
        title: String(localized: "URL cleaner", table: "Notchcast"),
        subtitle: String(localized: "Remove tracking parameters from copied links.", table: "Notchcast"),
        group: .system,
        defaultEnabled: false,
        backedUp: true,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
