import Foundation

extension NotchcastFeature.Descriptor {
    static let inUseMarks = Self(
        title: String(localized: "In-use marks", table: "Notchcast"),
        subtitle: String(localized: "Show when the camera or microphone is in use.", table: "Notchcast"),
        group: .music,
        defaultEnabled: true,
        backedUp: true,
        dependencies: [.island],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
