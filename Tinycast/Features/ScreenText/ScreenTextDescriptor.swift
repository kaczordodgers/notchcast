import Foundation

extension NotchcastFeature.Descriptor {
    static let screenText = Self(
        title: String(localized: "Capture Text", table: "Notchcast"),
        subtitle: String(localized: "Copy text from a selected screen area.", table: "Notchcast"),
        group: .captureAndDictation,
        defaultEnabled: true,
        backedUp: false,
        dependencies: [],
        requiredGrants: [.screenRecording],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
