import Foundation

enum TodoDateParser {
    typealias Language = TodoDateRules.Language

    private enum Attempt {
        case absent, invalid
        case parsed(TodoDateParse)
    }

    static func parse(_ text: String, now: Date, calendar: Calendar, timeZone: TimeZone,
                      preferredLanguage: Language) -> TodoDateParse? {
        var calendar = calendar
        calendar.timeZone = timeZone
        let languages: [Language] = [preferredLanguage, preferredLanguage == .english ? .polish : .english]
        let inputs = languages.map { NormalisedInput(text, language: $0) }
        for (language, input) in zip(languages, inputs) {
            switch dateAttempt(input, original: text, language: language, now: now, calendar: calendar) {
            case .parsed(let result): return result
            case .invalid: return nil
            case .absent: continue
            }
        }
        return timeAttempt(inputs[0], original: text, now: now, calendar: calendar)
    }

    private static func dateAttempt(_ input: NormalisedInput, original: String, language: Language,
                                    now: Date, calendar: Calendar) -> Attempt {
        let rules = language == .english ? TodoDateRules.englishRules : TodoDateRules.polishRules
        var matches: [(TodoDateRules.Kind, NSTextCheckingResult)] = []
        for rule in rules {
            for match in rule.expression.matches(in: input.text, range: input.fullRange)
                where !matches.contains(where: { NSIntersectionRange($0.1.range, match.range).length > 0 }) {
                matches.append((rule.kind, match))
            }
        }
        guard let (kind, match) = matches.max(by: { $0.1.range.location < $1.1.range.location }) else { return .absent }
        var matchedRange = match.range
        let suffixRange = NSRange(location: NSMaxRange(match.range), length: input.fullRange.length - NSMaxRange(match.range))
        let suffix = (input.text as NSString).substring(with: suffixRange)
        let timeMatch = TodoDateRules.timeSuffix.firstMatch(in: suffix, range: NSRange(suffix.startIndex..., in: suffix))
        let time = timeMatch.flatMap { wallTime(capture($0, 1, in: suffix)) }
        if let timeMatch {
            guard time != nil else { return .invalid }
            matchedRange.length += timeMatch.range.length
        }
        var recurrence: TodoRecurrenceRule?
        let day: Date?
        switch kind {
        case .recurrence:
            guard let rule = recurrenceRule(capture(match, 0, in: input.text), time: time) else { return .invalid }
            recurrence = rule
            day = initialDate(rule, now: now, calendar: calendar)
        case .relative:
            let phrase = capture(match, 0, in: input.text).lowercased()
            let offset = ["today": 0, "tomorrow": 1, "yesterday": -1,
                          "dayaftertomorrow": 2, "day after tomorrow": 2][phrase] ?? 0
            day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))
        case .offset:
            guard let interval = Int(capture(match, 1, in: input.text)), (1...10_000).contains(interval),
                  let unit = unit(capture(match, 2, in: input.text)) else { return .invalid }
            day = calendar.date(byAdding: unit.component, value: interval, to: calendar.startOfDay(for: now))
        case .weekday:
            guard let weekday = weekday(capture(match, 2, in: input.text)) else { return .invalid }
            var offset = (weekday - calendar.component(.weekday, from: now) + 7) % 7
            if !capture(match, 1, in: input.text).isEmpty { offset = offset == 0 ? 7 : offset }
            day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))
        case .iso:
            day = explicitDate(year: Int(capture(match, 1, in: input.text)),
                               month: Int(capture(match, 2, in: input.text)),
                               day: Int(capture(match, 3, in: input.text)), calendar: calendar)
        case .dayMonth, .monthDay:
            let monthIndex = kind == .dayMonth ? 2 : 1
            let dayIndex = kind == .dayMonth ? 1 : 2
            let month = TodoDateRules.months.firstIndex(of: capture(match, monthIndex, in: input.text).lowercased())
            day = explicitDate(year: Int(capture(match, 3, in: input.text)) ?? calendar.component(.year, from: now),
                               month: month.map { $0 + 1 }, day: Int(capture(match, dayIndex, in: input.text)),
                               calendar: calendar)
        case .numeric:
            let american = language == .english && capture(match, 2, in: input.text) == "/"
            day = explicitDate(year: Int(capture(match, 4, in: input.text)) ?? calendar.component(.year, from: now),
                               month: Int(capture(match, american ? 1 : 3, in: input.text)),
                               day: Int(capture(match, american ? 3 : 1, in: input.text)), calendar: calendar)
        }
        guard let day, let date = applying(time, to: day, calendar: calendar),
              let range = input.originalRange(matchedRange, in: original) else { return .invalid }
        return .parsed(result(date: date, time: time, recurrence: recurrence, range: range, calendar: calendar))
    }

    private static func timeAttempt(_ input: NormalisedInput, original: String, now: Date,
                                    calendar: Calendar) -> TodoDateParse? {
        let matches = TodoDateRules.timeOnly.matches(in: input.text, range: input.fullRange)
        for match in matches.reversed() {
            let phrase = capture(match, 0, in: input.text).trimmingCharacters(in: .whitespacesAndNewlines)
            let entire = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard phrase == entire || phrase.contains(":") || phrase.lowercased().hasSuffix("am")
                    || phrase.lowercased().hasSuffix("pm") || phrase.lowercased().hasPrefix("at ")
                    || phrase.lowercased().hasPrefix("o ") else { continue }
            guard let time = wallTime(capture(match, 1, in: input.text)),
                  let date = applying(time, to: now, calendar: calendar),
                  let range = input.originalRange(match.range, in: original) else { return nil }
            return result(date: date, time: time, recurrence: nil, range: range, calendar: calendar)
        }
        return nil
    }

    private static func result(date: Date, time: TodoRecurrenceRule.Time?, recurrence: TodoRecurrenceRule?,
                               range: Range<String.Index>, calendar: Calendar) -> TodoDateParse {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let dateString = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let normalised = recurrence?.canonicalString ?? dateString + (time.map { " at " + $0.canonicalString } ?? "")
        return TodoDateParse(date: date, time: time, allDay: time == nil, recurrence: recurrence,
                             normalised: normalised, matchedRange: range)
    }

    private static func recurrenceRule(_ text: String, time: TodoRecurrenceRule.Time?) -> TodoRecurrenceRule? {
        guard let match = TodoDateRules.scheduleParts.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        let prefix = capture(match, 1, in: text).lowercased()
        let count = capture(match, 2, in: text).lowercased()
        let interval = count == "second" ? 2 : (Int(count) ?? 1)
        guard (1...10_000).contains(interval) else { return nil }
        let base = capture(match, 3, in: text).lowercased()
        let on = capture(match, 4, in: text).lowercased()
        if prefix == "after" { return base == "day" || base == "days" ? .afterCompletion(days: interval) : nil }
        let weekday = weekday(base)
        let unit = weekday != nil ? TodoRecurrenceRule.Unit.week : (base == "last day" ? .month : unit(base))
        guard let unit else { return nil }
        var weekdays = weekday.map { [$0] } ?? []
        if on != "last day", !on.hasPrefix("day "), !on.isEmpty {
            weekdays = on.components(separatedBy: ",").compactMap {
                self.weekday($0.trimmingCharacters(in: .whitespaces))
            }
        }
        let day = base == "last day" || on == "last day" ? -1 : Int(on.replacingOccurrences(of: "day ", with: ""))
        guard let schedule = TodoRecurrenceRule.Schedule(interval: interval, unit: unit, weekdays: weekdays,
                                                        dayOfMonth: day, time: time) else { return nil }
        return prefix == "every!" ? .everyStrict(schedule) : .every(schedule)
    }

    private static func initialDate(_ rule: TodoRecurrenceRule, now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        let schedule: TodoRecurrenceRule.Schedule
        switch rule {
        case .afterCompletion(let days): return calendar.date(byAdding: .day, value: days, to: today)
        case .every(let value), .everyStrict(let value): schedule = value
        }
        if !schedule.weekdays.isEmpty {
            for offset in 0...7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      schedule.weekdays.contains(calendar.component(.weekday, from: day)) else { continue }
                if schedule.time == nil || applying(schedule.time, to: day, calendar: calendar).map({ $0 >= now }) == true {
                    return day
                }
            }
            return nil
        }
        if let requestedDay = schedule.dayOfMonth {
            guard let month = calendar.dateInterval(of: .month, for: now)?.start else { return nil }
            for offset in 0...12 {
                guard let start = calendar.date(byAdding: .month, value: offset, to: month),
                      let days = calendar.range(of: .day, in: .month, for: start) else { continue }
                let day = requestedDay == -1 ? days.count : requestedDay
                guard days.contains(day), let date = calendar.date(byAdding: .day, value: day - 1, to: start),
                      date >= today else { continue }
                if schedule.time == nil || applying(schedule.time, to: date, calendar: calendar).map({ $0 >= now }) == true {
                    return date
                }
            }
            return nil
        }
        if schedule.unit == .day {
            if schedule.time == nil || applying(schedule.time, to: today, calendar: calendar).map({ $0 >= now }) == true {
                return today
            }
        }
        return calendar.date(byAdding: schedule.unit.component, value: schedule.interval, to: today)
    }

    private static func explicitDate(year: Int?, month: Int?, day: Int?, calendar: Calendar) -> Date? {
        guard let year, let month, let day, (1...9999).contains(year), (1...12).contains(month),
              (1...31).contains(day), let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return nil
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return parts.year == year && parts.month == month && parts.day == day ? date : nil
    }

    private static func applying(_ time: TodoRecurrenceRule.Time?, to day: Date, calendar: Calendar) -> Date? {
        guard let time else { return calendar.startOfDay(for: day) }
        // Gaps preserve minutes by shifting forward; a repeated wall time uses its first occurrence.
        return calendar.nextDate(after: calendar.startOfDay(for: day).addingTimeInterval(-1),
                                 matching: DateComponents(hour: time.hour, minute: time.minute, second: 0),
                                 matchingPolicy: .nextTimePreservingSmallerComponents,
                                 repeatedTimePolicy: .first, direction: .forward)
    }

    private static func wallTime(_ text: String) -> TodoRecurrenceRule.Time? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = TodoDateRules.clockParts.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              var hour = Int(capture(match, 1, in: text)) else { return nil }
        let minute = Int(capture(match, 2, in: text)) ?? 0
        let meridiem = capture(match, 3, in: text).lowercased()
        if !meridiem.isEmpty {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (meridiem == "pm" ? 12 : 0)
        }
        return TodoRecurrenceRule.Time(hour: hour, minute: minute)
    }

    private static func weekday(_ text: String) -> Int? {
        TodoDateRules.weekdays.firstIndex(of: text.lowercased()).map { $0 + 1 }
    }

    private static func unit(_ text: String) -> TodoRecurrenceRule.Unit? {
        TodoRecurrenceRule.Unit.allCases.first { text.lowercased() == $0.rawValue || text.lowercased() == $0.rawValue + "s" }
    }

    private static func capture(_ match: NSTextCheckingResult, _ group: Int, in text: String) -> String {
        let range = match.range(at: group)
        return range.location == NSNotFound ? "" : (text as NSString).substring(with: range)
    }

    private struct NormalisedInput {
        var text: String
        var sourceRanges: [NSRange]
        var fullRange: NSRange { NSRange(location: 0, length: text.utf16.count) }

        init(_ original: String, language: Language) {
            text = original
            sourceRanges = (0..<original.utf16.count).map { NSRange(location: $0, length: 1) }
            let normalisations = language == .english
                ? TodoDateRules.englishNormalisations : TodoDateRules.polishNormalisations
            for normalisation in normalisations {
                let matches = normalisation.expression.matches(in: text, range: fullRange)
                for match in matches.reversed() {
                    let source = NSUnionRange(sourceRanges[match.range.location], sourceRanges[NSMaxRange(match.range) - 1])
                    sourceRanges.replaceSubrange(match.range.location..<NSMaxRange(match.range),
                                                 with: repeatElement(source, count: normalisation.replacement.utf16.count))
                    text = (text as NSString).replacingCharacters(in: match.range, with: normalisation.replacement)
                }
            }
        }

        func originalRange(_ range: NSRange, in original: String) -> Range<String.Index>? {
            guard range.length > 0 else { return nil }
            let source = NSUnionRange(sourceRanges[range.location], sourceRanges[NSMaxRange(range) - 1])
            return Range(source, in: original)
        }
    }
}
