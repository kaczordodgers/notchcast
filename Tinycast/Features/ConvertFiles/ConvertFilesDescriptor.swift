import Foundation

extension NotchcastFeature.Descriptor {
    static let convertFiles = Self(
        title: String(localized: "Convert Files", table: "Notchcast"),
        subtitle: String(localized: "Convert local files beside the originals.", table: "Notchcast"),
        group: .activities,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
