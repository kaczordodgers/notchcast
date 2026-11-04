// notchcast-sources: Tinycast/Features/Todo/Model/*.swift
import Foundation

@main
struct TodoDateParserTests {
    static func main() throws {
        guard let zone = TimeZone(identifier: "Europe/Warsaw") else { fatalError("Warsaw time zone") }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.firstWeekday = 2
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day,
                                                               hour: hour, minute: minute)) else { fatalError("Fixture date") }
            return date
        }
        let now = date(2026, 11, 3, 10)
        func parse(_ text: String, _ language: TodoDateParser.Language = .english,
                   at instant: Date? = nil) -> TodoDateParse? {
            TodoDateParser.parse(text, now: instant ?? now, calendar: calendar,
                                 timeZone: zone, preferredLanguage: language)
        }
        let phrases: [(String, String)] = [
            ("today", "2026-11-03"), ("Today", "2026-11-03"), ("TODAY", "2026-11-03"),
            ("tomorrow", "2026-11-04"), ("yesterday", "2026-11-02"), ("day after tomorrow", "2026-11-05"),
            ("tod", "2026-11-03"), ("tom", "2026-11-04"),
            ("monday", "2026-11-09"), ("tuesday", "2026-11-03"), ("wednesday", "2026-11-04"),
            ("thursday", "2026-11-05"), ("friday", "2026-11-06"), ("saturday", "2026-11-07"),
            ("sunday", "2026-11-08"), ("next wed", "2026-11-04"), ("next tuesday", "2026-11-10"),
            ("mon", "2026-11-09"), ("tue", "2026-11-03"), ("wed", "2026-11-04"),
            ("thu", "2026-11-05"), ("fri", "2026-11-06"), ("sat", "2026-11-07"), ("sun", "2026-11-08"),
            ("in 1 day", "2026-11-04"), ("in 3 days", "2026-11-06"), ("in 2 weeks", "2026-11-17"),
            ("in 1 month", "2026-12-03"), ("in 1 year", "2027-11-03"),
            ("5 nov", "2026-11-05"), ("5 november", "2026-11-05"), ("nov 5", "2026-11-05"),
            ("November 5, 2027", "2027-11-05"), ("5 nov 2027", "2027-11-05"),
            ("11/5", "2026-11-05"), ("2026-11-05", "2026-11-05"), ("5.11", "2026-11-05"),
            ("5.11.2027", "2027-11-05"), ("2028-02-29", "2028-02-29"),
            ("9", "2026-11-03 at 09:00"), ("9am", "2026-11-03 at 09:00"),
            ("9 pm", "2026-11-03 at 21:00"), ("12am", "2026-11-03 at 00:00"),
            ("12pm", "2026-11-03 at 12:00"), ("15:00", "2026-11-03 at 15:00"),
            ("o 9", "2026-11-03 at 09:00"), ("o 15:30", "2026-11-03 at 15:30"),
            ("at 9", "2026-11-03 at 09:00"), ("00:00", "2026-11-03 at 00:00"),
            ("23:59", "2026-11-03 at 23:59"), ("tomorrow 9", "2026-11-04 at 09:00"),
            ("tomorrow 9am", "2026-11-04 at 09:00"), ("tomorrow at 9", "2026-11-04 at 09:00"),
            ("next wed 15:00", "2026-11-04 at 15:00"), ("5 nov at 12pm", "2026-11-05 at 12:00"),
            ("jutro", "2026-11-04"), ("pojutrze", "2026-11-05"), ("dziś", "2026-11-03"),
            ("dzisiaj", "2026-11-03"), ("dzis", "2026-11-03"), ("wczoraj", "2026-11-02"),
            ("w poniedziałek", "2026-11-09"), ("we wtorek", "2026-11-03"), ("w środę", "2026-11-04"),
            ("w czwartek", "2026-11-05"), ("w piątek", "2026-11-06"), ("w sobotę", "2026-11-07"),
            ("w niedzielę", "2026-11-08"), ("poniedziałku", "2026-11-09"), ("poniedziałki", "2026-11-09"),
            ("wtorku", "2026-11-03"), ("wtorki", "2026-11-03"), ("środa", "2026-11-04"),
            ("środy", "2026-11-04"), ("środą", "2026-11-04"), ("środzie", "2026-11-04"),
            ("czwartku", "2026-11-05"), ("czwartki", "2026-11-05"), ("piątku", "2026-11-06"),
            ("piątki", "2026-11-06"), ("sobota", "2026-11-07"), ("soboty", "2026-11-07"),
            ("sobotą", "2026-11-07"), ("sobocie", "2026-11-07"), ("niedziela", "2026-11-08"),
            ("niedzieli", "2026-11-08"), ("niedzielą", "2026-11-08"), ("w srode", "2026-11-04"),
            ("w piatek", "2026-11-06"), ("za 3 dni", "2026-11-06"), ("za 1 dzień", "2026-11-04"),
            ("za 2 tygodnie", "2026-11-17"), ("za 3 miesiące", "2027-02-03"),
            ("5 listopada", "2026-11-05"), ("30 stycznia", "2026-01-30"), ("28 lutego", "2026-02-28"),
            ("2 marca", "2026-03-02"), ("3 kwietnia", "2026-04-03"), ("4 maja", "2026-05-04"),
            ("5 czerwca", "2026-06-05"), ("6 lipca", "2026-07-06"), ("7 sierpnia", "2026-08-07"),
            ("8 września", "2026-09-08"), ("9 października", "2026-10-09"), ("10 grudnia", "2026-12-10"),
            ("jutro o 9", "2026-11-04 at 09:00"), ("jutro o 15:30", "2026-11-04 at 15:30"),
            ("DZISIAJ O 9", "2026-11-03 at 09:00"), ("pojutrze 15:00", "2026-11-05 at 15:00")
        ]
        var checks = 0
        for (phrase, expected) in phrases {
            for language in [TodoDateParser.Language.english, .polish] {
                if phrase == "11/5", language == .polish { continue }
                guard let result = parse(phrase, language) else { fatalError("No date: \(phrase), \(language)") }
                precondition(result.normalised == expected, "\(phrase): \(result.normalised) != \(expected)")
                precondition(String(phrase[result.matchedRange]) == phrase, "Range: \(phrase)")
                precondition(result.allDay == !expected.contains(" at "), "All-day: \(phrase)")
                precondition(result.recurrence == nil, "One-off: \(phrase)")
                if let time = result.time {
                    precondition(calendar.component(.hour, from: result.date) == time.hour, "Hour: \(phrase)")
                    precondition(calendar.component(.minute, from: result.date) == time.minute, "Minute: \(phrase)")
                }
                checks += 1
            }
        }
        precondition(parse("11/5", .polish)?.normalised == "2026-05-11")
        let recurrences: [(String, String, String)] = [
            ("w każdy poniedziałek", "2026-11-09", "every 1 weeks on monday"),
            ("każdy poniedziałek", "2026-11-09", "every 1 weeks on monday"),
            ("every other monday", "2026-11-09", "every 2 weeks on monday"),
            ("co ostatni dzień miesiąca", "2026-11-30", "every 1 months on last day"),
            ("every monday at 9", "2026-11-09", "every 1 weeks on monday at 09:00"),
            ("every 2 weeks", "2026-11-17", "every 2 weeks"),
            ("every! day", "2026-11-03", "every! 1 days"),
            ("after 3 days", "2026-11-06", "after 3 days"),
            ("every last day", "2026-11-30", "every 1 months on last day"),
            ("every month on day 15", "2026-11-15", "every 1 months on day 15"),
            ("every week on monday,wednesday", "2026-11-04", "every 1 weeks on monday,wednesday"),
            ("every tuesday at 9", "2026-11-10", "every 1 weeks on tuesday at 09:00"),
            ("every tuesday at 15:00", "2026-11-03", "every 1 weeks on tuesday at 15:00"),
            ("every day at 9", "2026-11-04", "every 1 days at 09:00"),
            ("every! 2 days at 15:00", "2026-11-03", "every! 2 days at 15:00"),
            ("every 2 months", "2027-01-03", "every 2 months"),
            ("every year", "2027-11-03", "every 1 years"),
            ("daily", "2026-11-03", "every 1 days"),
            ("weekly", "2026-11-10", "every 1 weeks"),
            ("monthly", "2026-12-03", "every 1 months"),
            ("co tydzień", "2026-11-10", "every 1 weeks"),
            ("co poniedziałek", "2026-11-09", "every 1 weeks on monday"),
            ("co drugi poniedziałek", "2026-11-09", "every 2 weeks on monday"),
            ("codziennie", "2026-11-03", "every 1 days"),
            ("co miesiąc", "2026-12-03", "every 1 months"),
            ("co środę o 9", "2026-11-04", "every 1 weeks on wednesday at 09:00"),
            ("co 2 tygodnie", "2026-11-17", "every 2 weeks"),
            ("co ostatni dzień", "2026-11-30", "every 1 months on last day"),
            ("co! dzień", "2026-11-03", "every! 1 days")
        ]
        for (phrase, due, expected) in recurrences {
            for language in [TodoDateParser.Language.english, .polish] {
                guard let result = parse(phrase, language), let rule = result.recurrence else {
                    fatalError("No recurrence: \(phrase), \(language)")
                }
                precondition(rule.canonicalString == expected, "Recurrence \(phrase): \(rule.canonicalString)")
                let parts = calendar.dateComponents([.year, .month, .day], from: result.date)
                let actual = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
                precondition(actual == due, "Due \(phrase): \(actual)")
                precondition(parse(rule.canonicalString, language)?.recurrence == rule, "Canonical round trip: \(phrase)")
                let data = try JSONEncoder().encode(rule)
                let restored = try JSONDecoder().decode(TodoRecurrenceRule.self, from: data)
                precondition(restored == rule, "Codable round trip: \(phrase)")
                precondition(String(phrase[result.matchedRange]) == phrase, "Recurrence range: \(phrase)")
                checks += 1
            }
        }
        let invalid = ["feb 30", "30 lut", "2026-02-29", "2026-11-31", "31.04", "13/5", "00/5",
                       "2026-00-05", "2026-13-01", "2026-11-00", "29 lutego 2027", "April 31 at 9",
                       "25:00", "9:60", "0am", "13pm", "24", "tomorrow 25:00", "jutro o 9:60",
                       "every 0 days", "every 10001 days", "after 0 days", "in 999999999999999 days",
                       "Buy sun cream", "sat dish", "suncream", "satin",
                       "buy milk", "tomorrowland", "yesterdays", "p1", "buy 3 apples", "3-5pm"]
        for phrase in invalid {
            precondition(parse(phrase) == nil, "Invalid input accepted: \(phrase)")
            checks += 1
        }
        let embedded: [(String, String, String)] = [
            ("Buy milk tomorrow 9am #Home", "tomorrow 9am", "2026-11-04 at 09:00"),
            ("🛒 Kup mleko JUTRO o 9 #Dom", "JUTRO o 9", "2026-11-04 at 09:00"),
            ("jutro przez 2 godz", "jutro", "2026-11-04"),
            ("Zrób dziś przez 2 godz", "dziś", "2026-11-03"),
            ("🧑🏽‍💻 Praca w środę o 15:30!", "w środę o 15:30", "2026-11-04 at 15:30"),
            ("Call every monday at 9 #Work", "every monday at 9", "every 1 weeks on monday at 09:00"),
            ("today tomorrow", "tomorrow", "2026-11-04"),
            ("spotkanie 5 listopada 2027", "5 listopada 2027", "2027-11-05")
        ]
        for (text, matched, expected) in embedded {
            guard let result = parse(text) else { fatalError("Embedded date: \(text)") }
            precondition(String(text[result.matchedRange]) == matched, "Original range: \(text)")
            precondition(result.normalised == expected, "Embedded: \(text), \(result.normalised)")
            var title = text
            title.removeSubrange(result.matchedRange)
            precondition(!title.contains(matched), "Quick add strips only its date")
            checks += 1
        }
        guard let spring = parse("tomorrow 2:30", at: date(2026, 3, 28, 10)),
              let springPolish = parse("jutro o 2:30", at: date(2026, 3, 28, 10)),
              let autumn = parse("tomorrow 2:30", at: date(2026, 10, 24, 10)) else { fatalError("DST parse") }
        precondition(spring.date == date(2026, 3, 29, 3, 30), "Spring gap preserves minutes")
        precondition(springPolish.date == spring.date && spring.time?.hour == 2, "Requested wall time retained")
        precondition(autumn.date == date(2026, 10, 25, 2, 30), "First repeated wall time")
        precondition(zone.secondsFromGMT(for: autumn.date) == 7200, "Autumn chooses the summer-time occurrence")
        precondition(parse("tomorrow", at: date(2026, 3, 28, 10))?.date == date(2026, 3, 29), "All-day DST")
        precondition(parse("in 3 days", at: date(2026, 3, 28, 10))?.date == date(2026, 3, 31), "Calendar days across DST")
        var differentCalendarZone = calendar
        differentCalendarZone.timeZone = TimeZone(secondsFromGMT: 0) ?? zone
        let injected = TodoDateParser.parse("today", now: date(2026, 11, 3, 0, 30), calendar: differentCalendarZone,
                                            timeZone: zone, preferredLanguage: .english)
        precondition(injected?.date == date(2026, 11, 3), "Injected time zone overrides calendar zone")
        let clock = ContinuousClock()
        let start = clock.now
        var parsed = 0
        for index in 0..<1000 {
            let phrase = index.isMultiple(of: 2) ? "Buy milk tomorrow 9am #Home" : "Kup mleko jutro o 9 #Dom"
            if parse(phrase) != nil { parsed += 1 }
        }
        let elapsed = start.duration(to: clock.now)
        precondition(parsed == 1000 && elapsed < .milliseconds(500), "1000 parses: \(parsed), \(elapsed)")
        print("PASS: \(phrases.count + recurrences.count + invalid.count + embedded.count) phrase cases; \(checks) language checks")
        print("PASS: canonical and Codable recurrence round trips; Warsaw DST gap/fold; injected time zone")
        print("PASS: 1000 mixed-language parses in \(elapsed) (< 0.5 seconds)")
    }
}
