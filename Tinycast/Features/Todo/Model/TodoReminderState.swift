import Foundation

struct TodoReminderState: Codable, Equatable, Sendable {
    static let missedCutoff: TimeInterval = 24 * 60 * 60

    private(set) var lastCheck: Date?
    private(set) var firedIDs: Set<UUID>

    init(lastCheck: Date? = nil, firedIDs: Set<UUID> = []) {
        self.lastCheck = lastCheck
        self.firedIDs = firedIDs
    }

    mutating func check(_ schedule: TodoReminderSchedule) -> TodoReminderFire {
        let pending = schedule.remindersDue(at: schedule.now, excluding: firedIDs)
        firedIDs.formUnion(pending.map(\.reminder.id))
        lastCheck = max(lastCheck ?? schedule.now, schedule.now)
        let cutoff = schedule.now.addingTimeInterval(-Self.missedCutoff)
        return TodoReminderFire(
            checkedAt: schedule.now,
            due: pending.filter { $0.fireDate >= cutoff },
            missed: pending.filter { $0.fireDate < cutoff }
        )
    }

    mutating func rearm(_ reminderID: UUID) {
        firedIDs.remove(reminderID)
    }
}
