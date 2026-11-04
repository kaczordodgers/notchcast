import Foundation

nonisolated struct NotificationCleanupPolicy: Sendable {
    struct Alert: Sendable, Equatable {
        let identifier: String
        let title: String
        let isIndividualAlert: Bool
        let actions: [String]
    }

    let diskEjectionTitles: Set<String>

    func closeAction(for alert: Alert) -> String? {
        guard alert.isIndividualAlert, diskEjectionTitles.contains(alert.title) else { return nil }
        return alert.actions.first { $0 == "AXClose" || $0 == "Close" || $0.hasPrefix("Name:Close") }
    }
}
