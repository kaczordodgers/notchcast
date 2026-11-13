// notchcast-sources: Tinycast/Features/Todo/Model/*.swift
import Foundation

@main
struct TodoMaskedDateTests {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let text = "call tomorrow next #Home friday"
        let draft = TodoQuickAddParser.parse(text, projects: ["Home"]) { masked in
            guard let date = TodoDateParser.parse(masked, now: now, calendar: calendar,
                timeZone: calendar.timeZone, preferredLanguage: .english) else { return nil }
            return TodoQuickAddDate(range: NSRange(date.matchedRange, in: masked),
                display: date.normalised, payload: String(masked[date.matchedRange]))
        }
        precondition(draft.date?.payload == "friday", "A masked project must not stop date scanning")
        precondition(draft.title == "call tomorrow next")
        print("PASS: dates on both sides of a masked token remain discoverable")
    }
}
