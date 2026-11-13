import EventKit

enum EventReminderAlarms {
    static func offsets(_ alarms: [EKAlarm], start: Date) -> [TimeInterval] {
        alarms.map { $0.absoluteDate.map { $0.timeIntervalSince(start) } ?? $0.relativeOffset }
    }
}
