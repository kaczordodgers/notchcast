import Foundation

extension NotchcastFeature.Descriptor {
    static let quickLookSpace = Self(
        title: String(localized: "Quick Look on Space", table: "Notchcast"),
        subtitle: String(localized: "Preview an arrow-selected file with Space.", table: "Notchcast"),
        group: .launcher,
        defaultEnabled: true,
        backedUp: true,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
