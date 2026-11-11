import Foundation

extension NotchcastFeature.Descriptor {
    static let todoIsland = Self(
        title: String(localized: "Task island feed", table: "Notchcast"),
        subtitle: String(localized: "Prepare task snapshots for the island.", table: "Notchcast"),
        group: .tasks,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [.tasks],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
