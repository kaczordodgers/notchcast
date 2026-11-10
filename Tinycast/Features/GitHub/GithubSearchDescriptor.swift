import Foundation

extension NotchcastFeature.Descriptor {
    static let githubSearch = Self(
        title: String(localized: "GitHub Search", table: "Notchcast"),
        subtitle: String(localized: "Search GitHub repositories and starred projects.", table: "Notchcast"),
        group: .launcher,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
