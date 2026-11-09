import Foundation

extension NotchcastFeature.Descriptor {
    static let middleClick = Self(
        title: String(localized: "Trackpad Middle Click", table: "Notchcast"),
        subtitle: String(localized: "Three-finger taps and presses middle-click; paused during Three Finger Drag.", table: "Notchcast"),
        group: .system,
        defaultEnabled: true,
        dependencies: [],
        requiredGrants: [.accessibility],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
