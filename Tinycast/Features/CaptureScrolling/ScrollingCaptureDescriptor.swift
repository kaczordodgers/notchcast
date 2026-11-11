import Foundation

extension NotchcastFeature.Descriptor {
    static let scrollingCapture = Self(
        title: String(localized: "Scrolling Capture", table: "Notchcast"),
        subtitle: String(localized: "Copy a scrolling area as one image.", table: "Notchcast"),
        group: .captureAndDictation,
        defaultEnabled: true,
        dependencies: [],
        requiredGrants: [.screenRecording],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
