import Foundation

extension NotchcastFeature.Descriptor {
    static let switcherQuitKey = Self(
        title: String(localized: "Switcher Quit Key", table: "Notchcast"),
        subtitle: String(localized: "Press Q in an empty window search to quit the selected app.", table: "Notchcast"),
        group: .launcher,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [.accessibility],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
