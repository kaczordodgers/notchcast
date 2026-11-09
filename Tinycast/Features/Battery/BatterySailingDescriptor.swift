import Foundation

extension NotchcastFeature.Descriptor {
    static let batterySailing = Self(
        title: String(localized: "Battery Sailing", table: "Notchcast"),
        subtitle: String(localized: "Use battery power above the charge limit.", table: "Notchcast"),
        group: .systemTools,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: true,
        isSystemTweak: false
    )
}
