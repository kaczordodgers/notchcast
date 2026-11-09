import Foundation

extension NotchcastFeature.Descriptor {
    static let shelfBetweenMacs = Self(
        title: String(localized: "Shelf between Macs", table: "Notchcast"),
        subtitle: String(localized: "Send small items to the paired Mac.", table: "Notchcast"),
        group: .activities,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
