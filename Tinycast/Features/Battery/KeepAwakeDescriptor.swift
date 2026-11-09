import Foundation

extension NotchcastFeature.Descriptor {
    static let keepAwake = Self(
        title: String(localized: "Keep Awake", table: "Notchcast"),
        subtitle: String(localized: "Prevent idle sleep for the selected duration.", table: "Notchcast"),
        group: .systemTools,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: true,
        isSystemTweak: false
    )
}
