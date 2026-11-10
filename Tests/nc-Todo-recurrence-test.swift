// notchcast-sources: Tinycast/Features/Todo/Model/*.swift
import Foundation

@main
struct TodoRecurrenceTests {
    static func main() {
        guard let zone = TimeZone(identifier: "Europe/Warsaw") else { fatalError("Warsaw") }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.firstWeekday = 2
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
            guard let value = calendar.date(from: DateComponents(year: year, month: month, day: day,
                                                                 hour: hour, minute: minute)) else {
                fatalError("Fixture")
            }
            return value
        }
        func rule(_ phrase: String) -> TodoRecurrenceRule {
            guard let rule = TodoDateParser.parse(phrase, now: date(2026, 11, 4), calendar: calendar,
                                                  timeZone: zone, preferredLanguage: .english)?.recurrence else {
                fatalError("Rule: \(phrase)")
            }
            return rule
        }
        var monthly = rule("every month")
        var monthlyDue = date(2026, 1, 31)
        for expected in [date(2026, 2, 28), date(2026, 3, 31), date(2026, 4, 30)] {
            let outcome = TodoRecurrence(calendar: calendar).complete(TodoRecurringSnapshot(
                id: UUID(), due: monthlyDue, hasTime: false, rule: monthly, subtaskIDs: []), at: monthlyDue)
            precondition(outcome.due == expected)
            monthlyDue = outcome.due
            monthly = outcome.rule
        }
        var checks = 0
        func check(_ phrase: String, _ due: Date, _ completed: Date, _ expected: Date, timed: Bool = false) {
            let value = rule(phrase)
            let task = TodoRecurringSnapshot(id: UUID(), due: due, hasTime: timed, rule: value,
                                             subtaskIDs: [UUID(), UUID()])
            let outcome = TodoRecurrence(calendar: calendar).complete(task, at: completed)
            precondition(outcome.due == expected, "\(phrase): \(outcome.due) != \(expected)")
            precondition(outcome.id == task.id && outcome.subtaskIDsToReset == task.subtaskIDs)
            precondition(outcome.undoSnapshot == task, "Undo restores every snapshot field")
            precondition(rule(outcome.undoSnapshot.rule.canonicalString) == value, "Canonical round trip")
            checks += 1
        }
        check("every day", date(2026, 11, 1), date(2026, 11, 4, 12), date(2026, 11, 5))
        check("every! day", date(2026, 11, 1), date(2026, 11, 4, 12), date(2026, 11, 5))
        check("every 2 days", date(2026, 11, 1), date(2026, 11, 4, 12), date(2026, 11, 5))
        check("every! 2 days", date(2026, 11, 1), date(2026, 11, 4, 12), date(2026, 11, 6))
        check("every week", date(2026, 11, 1), date(2026, 11, 4, 12), date(2026, 11, 8))
        check("every! week", date(2026, 11, 1), date(2026, 11, 4, 12), date(2026, 11, 11))
        check("every 2 weeks", date(2026, 11, 1), date(2026, 11, 4), date(2026, 11, 15))
        check("after 3 days", date(2026, 11, 1, 9, 15), date(2026, 11, 4, 20),
              date(2026, 11, 7, 9, 15), timed: true)
        check("every month", date(2026, 1, 31), date(2026, 1, 31), date(2026, 2, 28))
        check("every! month", date(2026, 1, 31), date(2026, 2, 3), date(2026, 3, 3))
        check("every! year", date(2024, 2, 29), date(2026, 11, 4), date(2027, 11, 4))
        check("every month on day 31", date(2028, 1, 31), date(2028, 2, 1), date(2028, 2, 29))
        check("every month on day 31", date(2026, 1, 31), date(2026, 2, 28), date(2026, 3, 31))
        check("every last day", date(2026, 2, 28), date(2026, 2, 28), date(2026, 3, 31))
        check("every year", date(2024, 2, 29), date(2024, 2, 29), date(2025, 2, 28))
        check("every year", date(2024, 2, 29), date(2027, 3, 1), date(2028, 2, 29))
        check("every week on monday,wednesday", date(2026, 11, 2), date(2026, 11, 2), date(2026, 11, 4))
        check("every 2 weeks on monday,wednesday", date(2026, 11, 2), date(2026, 11, 4), date(2026, 11, 16))
        check("every day at 2:30", date(2026, 3, 28, 2, 30), date(2026, 3, 28, 12),
              date(2026, 3, 29, 3, 30), timed: true)
        check("every day at 2:30", date(2026, 10, 24, 2, 30), date(2026, 10, 24, 12),
              date(2026, 10, 25, 2, 30), timed: true)
        check("every day at 2:30", date(2026, 3, 29, 3, 30), date(2026, 3, 29, 12),
              date(2026, 3, 30, 2, 30), timed: true)
        check("every day", date(2026, 3, 28), date(2026, 3, 28, 12), date(2026, 3, 29))
        check("every day", date(2026, 11, 1, 15, 45), date(2026, 11, 4, 12),
              date(2026, 11, 5, 15, 45), timed: true)
        print("PASS: \(checks) recurrence cases; schedule/completion anchors, month-end, leap year, Warsaw DST")
        print("PASS: identity, unconditional subtask reset, exact undo and parser canonical round trips")
    }
}
