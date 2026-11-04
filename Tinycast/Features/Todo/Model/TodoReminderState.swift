import Foundation

struct TodoReminderState: Codable, Equatable, Sendable {
    static let missedCutoff: TimeInterval = 24 * 60 * 60

    private(set) var lastCheck: Date?
    struct Occurrence: Codable, Hashable, Sendable {
        let id: UUID
        let fireDate: Date
    }
    private(set) var firedIDs: Set<Occurrence>

    init(lastCheck: Date? = nil, firedIDs: Set<Occurrence> = []) {
        self.lastCheck = lastCheck
        self.firedIDs = firedIDs
    }

    mutating func check(_ schedule: TodoReminderSchedule) -> TodoReminderFire {
        let pending = schedule.remindersDue(at: schedule.now, excluding: firedIDs).filter { entry in
            entry.fireDate >= schedule.now.addingTimeInterval(-Self.missedCutoff)
                || (lastCheck.map { previous in
                    entry.fireDate > previous.addingTimeInterval(-Self.missedCutoff)
                } ?? true)
        }
        firedIDs.formUnion(pending.map { Occurrence(id: $0.reminder.id, fireDate: $0.fireDate) })
        lastCheck = max(lastCheck ?? schedule.now, schedule.now)
        let cutoff = schedule.now.addingTimeInterval(-Self.missedCutoff)
        firedIDs = firedIDs.filter { $0.fireDate >= cutoff }
        return TodoReminderFire(
            checkedAt: schedule.now,
            due: pending.filter { $0.fireDate >= cutoff },
            missed: pending.filter { $0.fireDate < cutoff }
        )
    }

}
