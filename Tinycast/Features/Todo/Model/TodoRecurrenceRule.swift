import Foundation

enum TodoRecurrenceRule: Codable, Equatable, Sendable {
    enum Unit: String, Codable, Sendable, CaseIterable {
        case day, week, month, year

        var component: Calendar.Component {
            switch self {
            case .day: .day
            case .week: .weekOfYear
            case .month: .month
            case .year: .year
            }
        }
    }

    struct Time: Codable, Equatable, Sendable {
        let hour: Int
        let minute: Int

        init?(hour: Int, minute: Int = 0) {
            guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
            self.hour = hour
            self.minute = minute
        }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let hour = try values.decode(Int.self, forKey: .hour)
            let minute = try values.decode(Int.self, forKey: .minute)
            guard let value = Self(hour: hour, minute: minute) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                        debugDescription: "Invalid wall time"))
            }
            self = value
        }

        var canonicalString: String { String(format: "%02d:%02d", hour, minute) }
    }

    struct Schedule: Codable, Equatable, Sendable {
        let interval: Int
        let unit: Unit
        // Calendar weekday numbering keeps Sunday = 1 regardless of the locale's first weekday.
        let weekdays: [Int]
        // The last day varies by month, so -1 retains the intent instead of freezing today's day.
        let dayOfMonth: Int?
        let time: Time?

        init?(interval: Int = 1, unit: Unit, weekdays: [Int] = [],
              dayOfMonth: Int? = nil, time: Time? = nil) {
            guard (1...10_000).contains(interval), weekdays.allSatisfy({ (1...7).contains($0) }),
                  weekdays.isEmpty || unit == .week,
                  dayOfMonth == nil || unit == .month,
                  dayOfMonth.map({ $0 == -1 || (1...31).contains($0) }) ?? true else { return nil }
            self.interval = interval
            self.unit = unit
            self.weekdays = Array(Set(weekdays)).sorted()
            self.dayOfMonth = dayOfMonth
            self.time = time
        }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let interval = try values.decode(Int.self, forKey: .interval)
            let unit = try values.decode(Unit.self, forKey: .unit)
            let weekdays = try values.decode([Int].self, forKey: .weekdays)
            let day = try values.decodeIfPresent(Int.self, forKey: .dayOfMonth)
            let time = try values.decodeIfPresent(Time.self, forKey: .time)
            guard let value = Self(interval: interval, unit: unit, weekdays: weekdays,
                                   dayOfMonth: day, time: time) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                        debugDescription: "Invalid recurrence schedule"))
            }
            self = value
        }
    }

    case every(Schedule)
    case everyStrict(Schedule)
    case afterCompletion(days: Int)

    func anchored(to due: Date, calendar: Calendar) -> Self {
        guard case .every(let schedule) = self, schedule.unit == .month,
              schedule.dayOfMonth == nil,
              let anchored = Schedule(interval: schedule.interval, unit: .month,
                  dayOfMonth: calendar.component(.day, from: due), time: schedule.time) else { return self }
        return .every(anchored)
    }

    var canonicalString: String {
        switch self {
        case .afterCompletion(let days): return "after \(days) days"
        case .every(let schedule): return canonical(schedule, prefix: "every")
        case .everyStrict(let schedule): return canonical(schedule, prefix: "every!")
        }
    }

    private func canonical(_ schedule: Schedule, prefix: String) -> String {
        var result = "\(prefix) \(schedule.interval) \(schedule.unit.rawValue)s"
        if !schedule.weekdays.isEmpty {
            result += " on " + schedule.weekdays.map { TodoDateRules.weekdays[$0 - 1] }.joined(separator: ",")
        }
        if let day = schedule.dayOfMonth {
            result += day == -1 ? " on last day" : " on day \(day)"
        }
        if let time = schedule.time { result += " at \(time.canonicalString)" }
        return result
    }
}
