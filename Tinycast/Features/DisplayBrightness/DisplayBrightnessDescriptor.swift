import Foundation

extension NotchcastFeature.Descriptor {
    static let displayBrightness = Self(
        title: String(localized: "Display Brightness", table: "Notchcast"),
        subtitle: String(localized: "Brightness keys control every display, external ones too.", table: "Notchcast"),
        group: .system,
        defaultEnabled: true,
        dependencies: [],
        requiredGrants: [.accessibility],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
