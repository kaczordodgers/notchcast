import Foundation

extension NotchcastFeature.Descriptor {
    static let markdownFiles = Self(
        title: String(localized: "Markdown Files", table: "Notchcast"),
        subtitle: String(localized: "Edit Markdown documents outside the notes folder.", table: "Notchcast"),
        group: .system,
        defaultEnabled: true,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
