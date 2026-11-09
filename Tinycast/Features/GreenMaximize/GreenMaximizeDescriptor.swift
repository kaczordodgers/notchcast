import Foundation

extension NotchcastFeature.Descriptor {
    static let greenMaximize = Self(
        title: String(localized: "Green Button Maximizes", table: "Notchcast"),
        subtitle: String(localized: "Click the green button to maximize or restore; hold Option for macOS behavior.", table: "Notchcast"),
        group: .system,
        defaultEnabled: true,
        dependencies: [],
        requiredGrants: [.accessibility],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
