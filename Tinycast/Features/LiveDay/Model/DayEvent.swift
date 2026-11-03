import Foundation

struct DayEvent: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarID: String

    static func current(in events: [Self], now: Date) -> Self? {
        events.filter { !$0.isAllDay && $0.start <= now && now < $0.end }
            .min { $0.end < $1.end }
    }

    static func next(in events: [Self], now: Date) -> Self? {
        events.filter { !$0.isAllDay && $0.start > now }.min { $0.start < $1.start }
    }
}
