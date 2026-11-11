import Foundation

extension NotchcastFeature.Descriptor {
    static let archivesDefaultApp = Self(
        title: String(localized: "Open archives with Notchcast", table: "Notchcast"),
        subtitle: String(localized: "Use Notchcast instead of Archive Utility to open archives.", table: "Notchcast"),
        group: .archives,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [.archives],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
