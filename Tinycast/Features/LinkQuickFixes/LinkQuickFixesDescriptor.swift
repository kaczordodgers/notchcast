import Foundation

extension NotchcastFeature.Descriptor {
    static let linkQuickFixes = Self(
        title: String(localized: "Link Quick Fixes", table: "Notchcast"),
        subtitle: String(localized: "Offer manual fixes for connection problems.", table: "Notchcast"),
        group: .systemTools,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: true,
        isSystemTweak: false
    )
}
