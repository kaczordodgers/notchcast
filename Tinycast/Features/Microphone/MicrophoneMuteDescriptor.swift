import Foundation

extension NotchcastFeature.Descriptor {
    static let microphoneMute = Self(
        title: String(localized: "Microphone mute", table: "Notchcast"),
        subtitle: String(localized: "Press F5 to mute or unmute microphones.", table: "Notchcast"),
        group: .music,
        defaultEnabled: true,
        backedUp: false,
        dependencies: [.island],
        requiredGrants: [.accessibility],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
