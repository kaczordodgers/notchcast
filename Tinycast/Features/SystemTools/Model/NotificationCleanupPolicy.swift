import Foundation

nonisolated struct NotificationCleanupPolicy: Sendable {
    struct Alert: Sendable, Equatable {
        let identifier: String
        let title: String
        let isIndividualAlert: Bool
        let actions: [String]
    }

    let diskEjectionTitles: Set<String>
    let closeNames: [String]
    let clearAllNames: [String]

    init(diskEjectionTitles: Set<String>, localizedClose: String = "Close", localizedClearAll: String = "Clear All") {
        self.diskEjectionTitles = diskEjectionTitles
        closeNames = [localizedClose, "Close"]
        clearAllNames = [localizedClearAll, "Clear All"]
    }

    func isStack(actions: [String]) -> Bool {
        actions.contains { action in clearAllNames.contains { action.hasPrefix("Name:\($0)") } }
    }

    func closeAction(for alert: Alert) -> String? {
        guard alert.isIndividualAlert, diskEjectionTitles.contains(alert.title) else { return nil }
        return alert.actions.first { action in
            action == "AXClose" || closeNames.contains { action == $0 || action.hasPrefix("Name:\($0)") }
        }
    }
}
