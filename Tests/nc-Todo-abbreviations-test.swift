// notchcast-sources: Tinycast/Features/Todo/Model/*.swift
import Foundation

@main
struct TodoAbbreviationTests {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar = Calendar(identifier: .gregorian)
        for text in ["Call Tom about the milk", "Ask Tod about lunch"] {
            precondition(TodoDateParser.parse(text, now: now, calendar: calendar,
                timeZone: calendar.timeZone, preferredLanguage: .english) == nil,
                "Names in prose must not become dates")
        }
        for text in ["tom", "tod", "tom 9am", "today", "tomorrow"] {
            precondition(TodoDateParser.parse(text, now: now, calendar: calendar,
                timeZone: calendar.timeZone, preferredLanguage: .english) != nil)
        }
        print("PASS: date abbreviations require scheduling context")
    }
}
