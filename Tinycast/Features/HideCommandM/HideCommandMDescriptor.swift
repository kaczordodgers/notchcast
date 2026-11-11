import Foundation

extension NotchcastFeature.Descriptor {
    static let hideCommandM = Self(
        title: String(localized: "Hide with ⌘M", table: "Notchcast"),
        subtitle: String(localized: "Hide the front app instead of minimizing its window.", table: "Notchcast"),
        group: .system,
        defaultEnabled: true,
        backedUp: true,
        dependencies: [],
        requiredGrants: [.accessibility],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
