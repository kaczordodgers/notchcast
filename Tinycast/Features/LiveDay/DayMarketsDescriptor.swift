import Foundation

extension NotchcastFeature.Descriptor {
    static let dayMarkets = Self(
        title: String(localized: "Markets", table: "Notchcast"),
        subtitle: String(localized: "Prices refresh every 3 minutes while Day is open.", table: "Notchcast"),
        group: .activities,
        defaultEnabled: true,
        dependencies: [.island],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
