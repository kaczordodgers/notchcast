import Foundation

extension NotchcastFeature.Descriptor {
    static let finderCutPaste = Self(
        title: String(localized: "Finder Cut and Paste", table: "Notchcast"),
        subtitle: String(localized: "Use ⌘X and ⌘V to move files in Finder.", table: "Notchcast"),
        group: .finder,
        defaultEnabled: true,
        backedUp: true,
        dependencies: [],
        requiredGrants: [.accessibility],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
