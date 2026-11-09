import Foundation

extension NotchcastFeature.Descriptor {
    static let pasteImage = Self(
        title: String(localized: "Paste Image in Finder", table: "Notchcast"),
        subtitle: String(localized: "Command+V saves clipboard images as PNG files in Finder.", table: "Notchcast"),
        group: .clipboard,
        defaultEnabled: true,
        dependencies: [],
        requiredGrants: [.accessibility],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
