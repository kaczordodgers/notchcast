import Foundation

extension NotchcastFeature.Descriptor {
    static let spotlightOff = Self(
        title: String(localized: "Spotlight Indexing Off", table: "Notchcast"),
        subtitle: String(localized: "Turn off Spotlight indexing.", table: "Notchcast"),
        group: .tweaks,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: true
    )
}
