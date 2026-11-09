import Foundation

extension NotchcastFeature.Descriptor {
    static let macSetup = Self(
        title: String(localized: "Mac Setup Presets", table: "Notchcast"),
        subtitle: String(localized: "Apply reversible macOS preferences.", table: "Notchcast"),
        group: .tweaks,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: true
    )
}
