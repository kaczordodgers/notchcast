import Foundation

extension NotchcastFeature.Descriptor {
    static let lidClosedAwake = Self(
        title: String(localized: "Keep Awake with Lid Closed", table: "Notchcast"),
        subtitle: String(localized: "Keep awake while the lid is closed.", table: "Notchcast"),
        group: .systemTools,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: true,
        isSystemTweak: false
    )
}
