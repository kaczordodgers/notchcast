import Foundation

struct EventReminderEngine {
    struct Event: Sendable {
        let id: String
        let title: String
        let start: Date
        let isAllDay: Bool
        let isDeclined: Bool
        let offsets: [TimeInterval]
    }

    struct Alert: Sendable {
        let event: Event
        let date: Date
        var key: String {
            "\(event.id)|\(event.start.timeIntervalSinceReferenceDate)|\(date.timeIntervalSinceReferenceDate)"
        }
    }

    private var shown: Set<String> = []
    private var horizon: Date

    init(armedAt: Date) { horizon = armedAt }

    mutating func evaluate(events: [Event], now: Date) -> (due: [Alert], next: Date?) {
        let alerts = events.filter { !$0.isAllDay && !$0.isDeclined }.flatMap { event in
            Set(event.offsets.filter { $0.isFinite && $0 <= 0 }).map {
                Alert(event: event, date: event.start.addingTimeInterval($0))
            }
        }.sorted { ($0.date, $0.key) < ($1.date, $1.key) }
        shown.formIntersection(Set(alerts.map(\.key)))
        let due = alerts.filter {
            $0.date > horizon && $0.date <= now && now < $0.event.start.addingTimeInterval(300)
                && !shown.contains($0.key)
        }
        shown.formUnion(due.map(\.key))
        horizon = now
        return (due, alerts.first { $0.date > now }?.date)
    }
}
