import Foundation

extension NotchcastFeature.Descriptor {
    static let machMBPFans = Self(
        title: String(localized: "Other Mac Fans", table: "Notchcast"),
        subtitle: String(localized: "Control fans on the paired Mac.", table: "Notchcast"),
        group: .system,
        defaultEnabled: false,
        dependencies: [.machLink],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
