// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Model/*.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityPreferences.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityStore.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/SystemTools/Model/NotificationCleanupPolicy.swift
// notchcast-sources: Tinycast/Features/SystemTools/Service/NotificationCleanupService.swift
// notchcast-sources: Tinycast/Features/SystemTools/UI/NotificationCleanupObserver.swift
import Foundation

@main
struct NotificationObserverTests {
    @MainActor
    static func main() throws {
        let policy = NotificationCleanupPolicy(diskEjectionTitles: ["Disk Not Ejected Properly"])
        let service = NotificationCleanupService(policy: policy)
        let selected = NotificationCleanupPolicy.Alert(identifier: "disk", title: "Disk Not Ejected Properly",
                                                       isIndividualAlert: true, actions: ["AXClose"])
        let unrelated = NotificationCleanupPolicy.Alert(identifier: "other", title: "Other",
                                                        isIndividualAlert: true, actions: ["AXClose"])
        let grouped = NotificationCleanupPolicy.Alert(identifier: "group", title: selected.title,
                                                      isIndividualAlert: false, actions: ["AXClose"])
        var performed: [String] = []
        let denied = try service.apply(alerts: [selected], trusted: false,
                                       current: { _ in preconditionFailure("Denied access") },
                                       perform: { _, _ in preconditionFailure("Denied dismissal") })
        precondition(denied == 0)
        let count = try service.apply(alerts: [selected, unrelated, grouped], trusted: true,
                                      current: { _ in selected }, perform: { id, _ in performed.append(id) })
        precondition(count == 1 && performed == ["disk"])
        let stale = try service.apply(alerts: [selected], trusted: true, current: { _ in unrelated },
                                      perform: { _, _ in preconditionFailure("Stale dismissal") })
        precondition(stale == 0)
        print("Notification cleanup: permission, selection and stale snapshot checks passed")
    }
}
