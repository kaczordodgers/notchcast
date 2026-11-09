import Foundation

extension NotchcastFeature.Descriptor {
    static let mediaTools = Self(
        title: String(localized: "Media Tools", table: "Notchcast"),
        subtitle: String(localized: "Compress media, make GIFs and extract text locally.", table: "Notchcast"),
        group: .activities,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
