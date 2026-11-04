import Foundation

struct TodoReminderSchedule: Sendable {
    struct Entry: Equatable, Sendable {
        let reminder: TodoReminder
        let fireDate: Date
    }

    let entries: [Entry]
    let now: Date

    init(
        reminders: [TodoReminder],
        taskExists: (String) -> Bool,
        dueDate: (String) -> (due: Date, hasTime: Bool)?,
        completedTaskIDs: Set<String>,
        snoozes: [UUID: Date],
        now: Date,
        calendar: Calendar
    ) {
        self.now = now
        var seen: Set<UUID> = []
        entries = reminders.compactMap { reminder -> Entry? in
            guard seen.insert(reminder.id).inserted,
                  !completedTaskIDs.contains(reminder.taskID), taskExists(reminder.taskID)
            else { return nil }
            let date: Date?
            if let snooze = snoozes[reminder.id] {
                date = snooze
            } else {
                switch reminder.kind {
                case .absolute(let absolute):
                    date = absolute
                case .relative(let minutes):
                    guard minutes >= 0, let due = dueDate(reminder.taskID) else { return nil }
                    let anchor = due.hasTime ? due.due : calendar.date(
                        bySettingHour: 9, minute: 0, second: 0, of: due.due
                    )
                    date = anchor?.addingTimeInterval(-Double(minutes) * 60)
                }
            }
            guard let date, date.timeIntervalSinceReferenceDate.isFinite else { return nil }
            return Entry(reminder: reminder, fireDate: date)
        }.sorted {
            if $0.fireDate != $1.fireDate { return $0.fireDate < $1.fireDate }
            return $0.reminder.id.uuidString < $1.reminder.id.uuidString
        }
    }

    func nextFireDate(excluding firedIDs: Set<TodoReminderState.Occurrence> = []) -> Date? {
        entries.first { $0.fireDate >= now.addingTimeInterval(-TodoReminderState.missedCutoff)
            && !firedIDs.contains(.init(id: $0.reminder.id, fireDate: $0.fireDate)) }.map { max(now, $0.fireDate) }
    }

    func remindersDue(at date: Date, excluding firedIDs: Set<TodoReminderState.Occurrence> = []) -> [Entry] {
        entries.prefix { $0.fireDate <= date }.filter {
            !firedIDs.contains(.init(id: $0.reminder.id, fireDate: $0.fireDate))
        }
    }
}
