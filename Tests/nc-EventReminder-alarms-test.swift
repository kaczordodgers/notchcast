// notchcast-sources: Tinycast/Features/EventReminder/Service/EventReminderAlarms.swift
// notchcast-sources: Tinycast/Features/EventReminder/Model/EventReminderEngine.swift
import EventKit

@main
struct ReminderAlarmsTest {
    static func main() {
        let start = Date(timeIntervalSince1970: 10_000)
        let alarms = [EKAlarm(absoluteDate: start.addingTimeInterval(-60)), EKAlarm(relativeOffset: -120)]
        let offsets = EventReminderAlarms.offsets(alarms, start: start)
        precondition(offsets == [-60, -120])
        var engine = EventReminderEngine(armedAt: start.addingTimeInterval(-180))
        let event = EventReminderEngine.Event(id: "event", title: "Event", start: start,
                                             isAllDay: false, isDeclined: false, offsets: offsets)
        precondition(engine.evaluate(events: [event], now: start.addingTimeInterval(-60)).due.count == 2)
        print("PASS absolute and relative EventKit alarms reach reminder delivery")
    }
}
