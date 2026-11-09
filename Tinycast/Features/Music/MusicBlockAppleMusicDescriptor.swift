import Foundation

extension NotchcastFeature.Descriptor {
    static let musicBlockAppleMusic = Self(
        title: String(localized: "Stop Apple Music opening on media keys", table: "Notchcast"),
        subtitle: String(localized: "Prevent media keys from launching Apple Music.", table: "Notchcast"),
        group: .music,
        defaultEnabled: true,
        dependencies: [.island],
        requiredGrants: [.accessibility],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
