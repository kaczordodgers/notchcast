import Foundation

extension NotchcastFeature.Descriptor {
    static let fanControl = Self(
        title: String(localized: "Fan Control", table: "Notchcast"),
        subtitle: String(localized: "Control fans with the privileged helper.", table: "Notchcast"),
        group: .systemTools,
        defaultEnabled: false,
        dependencies: [.systemMonitor],
        requiredGrants: [],
        isSystemFeature: true,
        isSystemTweak: false
    )
}
