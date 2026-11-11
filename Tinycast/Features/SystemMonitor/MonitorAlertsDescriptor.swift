import Foundation

extension NotchcastFeature.Descriptor {
    static let monitorAlerts = Self(
        title: String(localized: "Monitor Alerts", table: "Notchcast"),
        subtitle: String(localized: "Sample your Mac in the background while alerts are on.", table: "Notchcast"),
        group: .systemTools,
        defaultEnabled: false,
        backedUp: true,
        dependencies: [.systemMonitor],
        requiredGrants: [],
        isSystemFeature: true,
        isSystemTweak: false
    )
}
