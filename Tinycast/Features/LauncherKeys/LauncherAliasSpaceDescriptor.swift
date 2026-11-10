import Foundation

extension NotchcastFeature.Descriptor {
    static let launcherAliasSpace = Self(
        title: String(localized: "Alias and Space", table: "Notchcast"),
        subtitle: String(localized: "Press Space after an exact alias to open its command.", table: "Notchcast"),
        group: .launcher,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
