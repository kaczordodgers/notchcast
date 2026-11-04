import Foundation

nonisolated struct NotificationCleanupService: Sendable {
    let policy: NotificationCleanupPolicy

    func apply(alerts: [NotificationCleanupPolicy.Alert], trusted: Bool,
               current: (String) throws -> NotificationCleanupPolicy.Alert?,
               perform: (String, String) throws -> Void) throws -> Int {
        guard trusted else { return 0 }
        var count = 0
        for alert in alerts {
            guard let action = policy.closeAction(for: alert),
                  let refreshed = try current(alert.identifier), refreshed == alert else { continue }
            try perform(alert.identifier, action)
            count += 1
        }
        return count
    }
}
