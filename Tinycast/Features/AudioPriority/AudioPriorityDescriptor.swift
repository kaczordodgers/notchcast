import Foundation

extension NotchcastFeature.Descriptor {
    static let audioPriority = Self(
        title: String(localized: "Audio device priority", table: "Notchcast"),
        subtitle: String(localized: "Choose devices automatically when they connect or disconnect.", table: "Notchcast"),
        group: .systemTools,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: true,
        isSystemTweak: false
    )
}
