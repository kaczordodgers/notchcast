import Foundation

extension NotchcastFeature.Descriptor {
    static let colorPicker = Self(
        title: String(localized: "Color Picker", table: "Notchcast"),
        subtitle: String(localized: "Copy a color from anywhere on the screen.", table: "Notchcast"),
        group: .captureAndDictation,
        defaultEnabled: true,
        backedUp: true,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
