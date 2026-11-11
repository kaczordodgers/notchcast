import Foundation

extension NotchcastFeature.Descriptor {
    static let finderRename = Self(
        title: String(localized: "Finder Rename", table: "Notchcast"),
        subtitle: String(localized: "Use Hyper+R to rename the selection in Finder.", table: "Notchcast"),
        group: .finder,
        defaultEnabled: true,
        backedUp: true,
        dependencies: [],
        requiredGrants: [.accessibility],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
