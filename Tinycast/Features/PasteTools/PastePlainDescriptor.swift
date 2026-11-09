import Foundation

extension NotchcastFeature.Descriptor {
    static let pastePlain = Self(
        title: String(localized: "Paste Plain Text", table: "Notchcast"),
        subtitle: String(localized: "Paste text without formatting from the launcher.", table: "Notchcast"),
        group: .clipboard,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [.accessibility],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
