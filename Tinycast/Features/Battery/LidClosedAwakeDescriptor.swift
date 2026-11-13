import Foundation

extension NotchcastFeature.Descriptor {
    static let lidClosedAwake = Self(
        title: String(localized: "Keep Awake with Lid Closed", table: "Notchcast"),
        subtitle: String(localized: "Requires Keep Awake to be active while the lid is closed.", table: "Notchcast"),
        group: .systemTools,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: true,
        isSystemTweak: false
    )
}
