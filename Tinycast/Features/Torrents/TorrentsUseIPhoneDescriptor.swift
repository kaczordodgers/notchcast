import Foundation

extension NotchcastFeature.Descriptor {
    static let torrentsUseIPhone = Self(
        title: String(localized: "Use a plugged-in iPhone for big downloads", table: "Notchcast"),
        subtitle: String(localized: "Use Wi-Fi and iPhone USB Personal Hotspot together.", table: "Notchcast"),
        group: .torrents,
        defaultEnabled: true,
        dependencies: [.torrents],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
