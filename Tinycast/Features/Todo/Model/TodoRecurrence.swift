import Foundation

struct TodoRecurringSnapshot: Equatable, Sendable {
    let id: UUID
    let due: Date
    let hasTime: Bool
    let rule: TodoRecurrenceRule
    let subtaskIDs: [UUID]
}

struct TodoRecurrenceOutcome: Equatable, Sendable {
    let id: UUID
    let due: Date
    // Every occurrence starts with all subtasks reset, regardless of their previous state.
    let subtaskIDsToReset: [UUID]
    let rule: TodoRecurrenceRule
    let undoSnapshot: TodoRecurringSnapshot
}

struct TodoRecurrence: Sendable {
    let calendar: Calendar

    func complete(_ task: TodoRecurringSnapshot, at completedAt: Date) -> TodoRecurrenceOutcome {
        TodoRecurrenceOutcome(id: task.id,
                              due: Self.nextDue(task.rule, currentDue: task.due, hasTime: task.hasTime,
                                                completedAt: completedAt, calendar: calendar),
                              subtaskIDsToReset: task.subtaskIDs,
                              rule: task.rule.anchored(to: task.due, calendar: calendar), undoSnapshot: task)
    }

    static func nextDue(_ rule: TodoRecurrenceRule, currentDue: Date, hasTime: Bool,
                        completedAt: Date, calendar: Calendar) -> Date {
        let completionDay = calendar.startOfDay(for: completedAt)
        switch rule {
        case .afterCompletion(let days):
            precondition(days > 0, "Recurrence days must be positive")
            let day = adding(.day, value: days, to: completionDay, calendar: calendar)
            return wallTime(on: day, original: currentDue, time: nil, hasTime: hasTime, calendar: calendar)
        case .every(let schedule):
            // Due-date anchoring keeps interval phase even when several occurrences were missed.
            return nextSlot(schedule, anchor: currentDue, threshold: max(currentDue, completionDay),
                            completionDay: completionDay, original: currentDue,
                            hasTime: hasTime, calendar: calendar)
        case .everyStrict(let schedule):
            // Strict recurrence starts a fresh interval on completion day, keeping the due wall time.
            return nextSlot(schedule, anchor: completionDay, threshold: completionDay,
                            completionDay: completionDay, original: currentDue,
                            hasTime: hasTime, calendar: calendar)
        }
    }

    private static func nextSlot(_ schedule: TodoRecurrenceRule.Schedule, anchor: Date,
                                 threshold: Date, completionDay: Date, original: Date,
                                 hasTime: Bool, calendar: Calendar) -> Date {
        let anchorDay = calendar.startOfDay(for: anchor)
        if !schedule.weekdays.isEmpty {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: anchorDay)?.start else {
                preconditionFailure("Calendar cannot represent the anchor week")
            }
            var day = max(anchorDay, calendar.startOfDay(for: threshold))
            while true {
                let weeks = calendar.dateComponents([.weekOfYear], from: week, to: day).weekOfYear ?? 0
                if weeks.isMultiple(of: schedule.interval),
                   schedule.weekdays.contains(calendar.component(.weekday, from: day)),
                   day > completionDay {
                    let slot = wallTime(on: day, original: original, time: schedule.time,
                                        hasTime: hasTime, calendar: calendar)
                    if slot > threshold { return slot }
                }
                day = adding(.day, value: 1, to: day, calendar: calendar)
            }
        }
        var offset = 1
        while true {
            var day = adding(schedule.unit.component, value: offset * schedule.interval,
                             to: anchorDay, calendar: calendar)
            if let requested = schedule.dayOfMonth {
                guard let range = calendar.range(of: .day, in: .month, for: day) else {
                    preconditionFailure("Calendar cannot represent the target month")
                }
                let target = requested == -1 ? range.count : min(requested, range.count)
                day = adding(.day, value: target - calendar.component(.day, from: day),
                             to: day, calendar: calendar)
            }
            let slot = wallTime(on: day, original: original, time: schedule.time,
                                hasTime: hasTime, calendar: calendar)
            // Overdue occurrences skip completion day, including a timed slot later that day.
            if slot > threshold, day > completionDay { return slot }
            offset += 1
        }
    }

    private static func adding(_ component: Calendar.Component, value: Int, to date: Date,
                               calendar: Calendar) -> Date {
        guard let result = calendar.date(byAdding: component, value: value, to: date) else {
            preconditionFailure("Calendar cannot represent the next recurrence")
        }
        return result
    }

    private static func wallTime(on day: Date, original: Date, time: TodoRecurrenceRule.Time?,
                                 hasTime: Bool, calendar: Calendar) -> Date {
        guard hasTime else { return calendar.startOfDay(for: day) }
        let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: original)
        let match = DateComponents(hour: time?.hour ?? parts.hour, minute: time?.minute ?? parts.minute,
                                   second: parts.second, nanosecond: parts.nanosecond)
        // Preserve minutes through gaps and choose the first occurrence in a repeated hour.
        guard let result = calendar.nextDate(after: calendar.startOfDay(for: day).addingTimeInterval(-1),
                                             matching: match, matchingPolicy: .nextTimePreservingSmallerComponents,
                                             repeatedTimePolicy: .first) else {
            preconditionFailure("Calendar cannot represent the recurrence time")
        }
        return result
    }
}
