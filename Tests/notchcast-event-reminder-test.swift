// notchcast-sources: Tinycast/Features/EventReminder/Model/*.swift
import Foundation

@main
struct EventReminderTest {
    @MainActor
    final class FakeSource: EventReminderSource {
        var events: [EventReminderEngine.Event] = []
        func reminderEvents(in interval: DateInterval) -> [EventReminderEngine.Event] { events }
    }

    @MainActor
    static func main() {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let source = FakeSource()
        func event(_ id: String = "series", start: Date, allDay: Bool = false,
                   declined: Bool = false, offsets: [Double] = [-600, 0]) -> EventReminderEngine.Event {
            .init(id: id, title: "Meeting", start: start, isAllDay: allDay,
                  isDeclined: declined, offsets: offsets)
        }
        let start = clock.addingTimeInterval(1200)
        source.events = [event(start: start), event("all", start: start, allDay: true),
                         event("declined", start: start, declined: true)]
        var engine = EventReminderEngine(armedAt: clock)
        func evaluate() -> (due: [EventReminderEngine.Alert], next: Date?) {
            engine.evaluate(events: source.reminderEvents(in: DateInterval(start: clock, duration: 86400)), now: clock)
        }
        assert(evaluate().next == start.addingTimeInterval(-600))
        clock = start.addingTimeInterval(-600)
        assert(evaluate().due.count == 1)
        assert(evaluate().due.isEmpty)
        clock = start
        assert(evaluate().due.count == 1)
        source.events = [event(start: start.addingTimeInterval(86400))]
        clock = start.addingTimeInterval(86400)
        assert(evaluate().due.count == 2)
        clock = start.addingTimeInterval(90000)
        assert(evaluate().due.isEmpty)
        for date in ["2026-03-08T07:00:00Z", "2026-11-01T06:00:00Z"] {
            let occurrence = ISO8601DateFormatter().date(from: date)!
            var edge = EventReminderEngine(armedAt: occurrence.addingTimeInterval(-1200))
            let events = [event(start: occurrence, offsets: [-600, -600, .nan, .infinity, 10])]
            let result = edge.evaluate(events: events, now: occurrence.addingTimeInterval(-600))
            assert(result.due.count == 1)
            assert(result.due[0].date == occurrence.addingTimeInterval(-600))
        }
        print("event-reminder: passed lead, all-day, declined, recurrence, duplicates, stale, DST")
    }
}
