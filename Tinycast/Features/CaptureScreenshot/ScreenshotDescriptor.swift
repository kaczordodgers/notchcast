import Foundation

extension NotchcastFeature.Descriptor {
    static let screenshot = Self(
        title: String(localized: "Screenshots", table: "Notchcast"),
        subtitle: String(localized: "Capture an area, window or display.", table: "Notchcast"),
        group: .captureAndDictation,
        defaultEnabled: true,
        dependencies: [],
        requiredGrants: [.screenRecording],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
