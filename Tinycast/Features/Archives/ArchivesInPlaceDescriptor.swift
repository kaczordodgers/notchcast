import Foundation

extension NotchcastFeature.Descriptor {
    static let archivesInPlace = Self(
        title: String(localized: "Extract in place", table: "Notchcast"),
        subtitle: String(localized: "The archive shrinks while extracting.", table: "Notchcast"),
        group: .archives,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [.archives],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
