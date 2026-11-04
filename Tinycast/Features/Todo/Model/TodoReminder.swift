import Foundation

struct TodoReminder: Identifiable, Codable, Equatable, Sendable {
    enum Kind: Codable, Equatable, Sendable {
        case absolute(Date)
        case relative(minutesBeforeDue: Int)
    }

    enum Snooze: Codable, Sendable {
        case fiveMinutes
        case fifteenMinutes
        case oneHour
        case tomorrowMorning

        func fireDate(now: Date, calendar: Calendar) -> Date? {
            switch self {
            case .fiveMinutes: now.addingTimeInterval(5 * 60)
            case .fifteenMinutes: now.addingTimeInterval(15 * 60)
            case .oneHour: now.addingTimeInterval(60 * 60)
            case .tomorrowMorning:
                calendar.date(byAdding: .day, value: 1, to: now).flatMap {
                    calendar.date(bySettingHour: 9, minute: 0, second: 0, of: $0)
                }
            }
        }
    }

    let id: UUID
    let taskID: String
    var kind: Kind
}
