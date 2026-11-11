import Foundation

extension NotchcastFeature.Descriptor {
    static let tasksSync = Self(
        title: String(localized: "Sync tasks between Macs", table: "Notchcast"),
        subtitle: String(localized: "Exchange tasks with your paired Mac over Mac Link.", table: "Notchcast"),
        group: .tasks,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [.tasks, .machLink],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
