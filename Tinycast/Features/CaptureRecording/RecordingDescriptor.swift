import Foundation

extension NotchcastFeature.Descriptor {
    static let recording = Self(
        title: String(localized: "Screen Recording", table: "Notchcast"),
        subtitle: String(localized: "Record an area, window or display with system audio.", table: "Notchcast"),
        group: .captureAndDictation,
        defaultEnabled: true,
        backedUp: false,
        dependencies: [],
        requiredGrants: [.screenRecording],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
