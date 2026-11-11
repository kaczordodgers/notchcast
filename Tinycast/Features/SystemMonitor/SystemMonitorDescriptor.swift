import Foundation

extension NotchcastFeature.Descriptor {
    static let systemMonitor = Self(
        title: String(localized: "System Monitor", table: "Notchcast"),
        subtitle: String(localized: "Monitor system performance.", table: "Notchcast"),
        group: .systemTools,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: true,
        isSystemTweak: false
    )
}
