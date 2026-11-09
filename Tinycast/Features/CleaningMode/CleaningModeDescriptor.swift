import Foundation

extension NotchcastFeature.Descriptor {
    static let cleaningMode = Self(
        title: String(localized: "Cleaning mode", table: "Notchcast"),
        subtitle: String(localized: "Press Escape five times to exit; ends after 300 seconds.", table: "Notchcast"),
        group: .tools,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [.accessibility],
        isSystemFeature: true,
        isSystemTweak: false
    )
}
