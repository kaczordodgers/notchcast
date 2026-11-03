import Foundation

enum LiveTimerInput {
    static let defaultDuration: TimeInterval = 15 * 60
    static let maximumDuration: TimeInterval = 99 * 3600

    static func duration(_ text: String) -> TimeInterval? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.wholeMatch(of: /[0-9]+/) != nil, let minutes = Double(text) {
            return valid(minutes * 60)
        }
        let compact = text.filter { !$0.isWhitespace }
        let matches = compact.matches(of: /([0-9]+)([hms])/)
        guard !matches.isEmpty, matches.reduce(0, { $0 + $1.output.0.count }) == compact.count else {
            return nil
        }
        var seconds: TimeInterval = 0
        for match in matches {
            guard let count = Double(match.output.1) else { return nil }
            let multiplier: Double = switch match.output.2 { case "h": 3600; case "m": 60; default: 1 }
            seconds += count * multiplier
        }
        return valid(seconds)
    }

    static func alarm(_ text: String, now: Date, calendar: Calendar) -> Date? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = text.wholeMatch(of: /([0-9]{1,2}):([0-9]{2})/),
              let hour = Int(match.1), let minute = Int(match.2), hour < 24, minute < 60 else { return nil }
        return calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: minute, second: 0),
                                 matchingPolicy: .nextTime, repeatedTimePolicy: .first)
    }

    static func label(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
    }

    private static func valid(_ seconds: TimeInterval) -> TimeInterval? {
        seconds.isFinite && (1...maximumDuration).contains(seconds) ? seconds : nil
    }
}
