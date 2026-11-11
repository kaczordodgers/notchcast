import Foundation

extension NotchcastFeature.Descriptor {
    static let captureEditor = Self(
        title: String(localized: "Capture Editor", table: "Notchcast"),
        subtitle: String(localized: "Mark up a capture and copy it.", table: "Notchcast"),
        group: .captureAndDictation,
        defaultEnabled: false,
        backedUp: true,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
