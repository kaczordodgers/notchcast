import Foundation

extension NotchcastFeature.Descriptor {
    static let mediaTools = Self(
        title: String(localized: "Media Tools", table: "Notchcast"),
        subtitle: String(localized: "Compress media, make GIFs and extract text locally.", table: "Notchcast"),
        group: .activities,
        defaultEnabled: false,
        backedUp: true,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
