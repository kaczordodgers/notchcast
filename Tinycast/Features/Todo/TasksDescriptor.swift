import Foundation

extension NotchcastFeature.Descriptor {
    static let tasks = Self(
        title: String(localized: "Tasks", table: "Notchcast"),
        subtitle: String(localized: "Keep tasks on this Mac.", table: "Notchcast"),
        group: .tasks,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
