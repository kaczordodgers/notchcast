import Foundation

extension NotchcastFeature.Descriptor {
    static let fleetPanel = Self(
        title: String(localized: "Fleet Panel", table: "Notchcast"),
        subtitle: String(localized: "Read T3 Code threads on both Macs on demand.", table: "Notchcast"),
        group: .activities,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
