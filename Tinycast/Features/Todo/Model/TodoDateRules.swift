import Foundation

enum TodoDateRules {
    enum Language: String, Sendable {
        case english, polish
    }

    enum Kind: Sendable {
        case recurrence, relative, offset, weekday, iso, dayMonth, monthDay, numeric
    }

    struct Rule: Sendable {
        let kind: Kind
        let expression: NSRegularExpression
    }

    struct Normalisation: Sendable {
        let expression: NSRegularExpression
        let replacement: String
    }

    static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    static let months = ["january", "february", "march", "april", "may", "june",
                         "july", "august", "september", "october", "november", "december"]
    static let weekday = "(?:" + weekdays.joined(separator: "|") + ")"
    static let month = "(?:" + months.joined(separator: "|") + ")"
    static let clock = #"(?:[0-9]{1,2}(?::[0-9]{2})?(?:\s*(?:am|pm))?)(?![\p{L}\p{N}:])"#
    static let timeSuffix = regex(#"^\s+(?:(?:at|o)\s+)?("# + clock + ")")
    static let timeOnly = regex(#"(?<![\p{L}\p{N}:./-])(?:(?:at|o)\s+)?("# + clock + ")")
    static let clockParts = regex(#"^([0-9]{1,2})(?::([0-9]{2}))?\s*(am|pm)?$"#)
    static let scheduleParts = regex(
        #"^(every!?|after)\s+(?:(second|[0-9]+)\s+)?(last day|"# + weekday
        + #"|days?|weeks?|months?|years?)(?:\s+on\s+(last day|day\s+[0-9]+|"#
        + weekday + #"(?:\s*,\s*"# + weekday + #")*))?$"#)

    static let abbreviationContext = #"(?=\s*$|\s+(?:(?:at|o)\s+)?[0-9]|\s+(?:on|next|today|tomorrow)\b)"#

    static let englishNormalisations: [Normalisation] = normalisations([
        (#"every other"#, "every second"),
        (#"tod(?:ay)?"#, "today"), (#"tom(?:orrow)?"#, "tomorrow"),
        (#"daily"#, "every day"), (#"weekly"#, "every week"), (#"monthly"#, "every month"),
        (#"mon"# + abbreviationContext, "monday"), (#"tue(?:s)?"# + abbreviationContext, "tuesday"),
        (#"wed"# + abbreviationContext, "wednesday"), (#"thu(?:rs)?"# + abbreviationContext, "thursday"),
        (#"fri"# + abbreviationContext, "friday"),
        (#"sat"# + abbreviationContext, "saturday"),
        (#"sun"# + abbreviationContext, "sunday")
    ] + zip(["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep(?:t)?", "oct", "nov", "dec"],
            months).map { ($0.0, $0.1) })

    static let polishNormalisations: [Normalisation] = normalisations([
        (#"every other"#, "every second"),
        (#"co ostatni dzień miesiąca"#, "every last day"),
        (#"dziś|dzis|dzisiaj"#, "today"), (#"jutro"#, "tomorrow"), (#"pojutrze"#, "dayaftertomorrow"),
        (#"wczoraj"#, "yesterday"), (#"codziennie"#, "every day"),
        (#"(?:w\s+)?każdy|kazdy|co"#, "every"), (#"drugi|drugą|druga"#, "second"), (#"za"#, "in"),
        (#"następny|nastepny|następną|nastepna|przyszły|przyszly|przyszłą|przyszla"#, "next"),
        (#"poniedzia[łl](?:ek|ku|ki|ka|kiem|kom|kami|kach|ków|kow)|pon"#, "monday"),
        (#"wtorek|wtork(?:u|i|a|iem|om|ami|ach|ów|ow)|wt"#, "tuesday"),
        (#"[śs]rod(?:a|ę|e|y|ą|om|ami|ach)|[śs]rodzie|[śs]ród|srod|śr|sr"#, "wednesday"),
        (#"czwartek|czwartk(?:u|i|a|iem|om|ami|ach|ów|ow)|czw"#, "thursday"),
        (#"pi[ąa]tek|pi[ąa]tk(?:u|i|a|iem|om|ami|ach|ów|ow)|pt"#, "friday"),
        (#"sobot(?:a|ę|e|y|ą|om|ami|ach)|sobocie|sobót|sobot|sob"#, "saturday"),
        (#"niedziel(?:a|ę|e|i|ą|om|ami|ach)|niedz"#, "sunday"),
        (#"dzień|dzien|dni|dnia"#, "day"), (#"tydzień|tydzien|tygodnie|tygodni"#, "week"),
        (#"miesiąc|miesiac|miesiące|miesiace|miesięcy|miesiecy"#, "month"),
        (#"rok|lata|lat"#, "year"), (#"ostatni"#, "last"),
        (#"styczeń|styczen|stycznia|sty"#, "january"), (#"luty|lutego|lut"#, "february"),
        (#"marzec|marca|mar"#, "march"), (#"kwiecień|kwiecien|kwietnia|kwi"#, "april"),
        (#"maj|maja"#, "may"), (#"czerwiec|czerwca|cze"#, "june"),
        (#"lipiec|lipca|lip"#, "july"), (#"sierpień|sierpien|sierpnia|sie"#, "august"),
        (#"wrzesień|wrzesien|września|wrzesnia|wrz"#, "september"),
        (#"październik|pazdziernik|października|pazdziernika|paź|paz"#, "october"),
        (#"listopad|listopada|lis"#, "november"), (#"grudzień|grudzien|grudnia|gru"#, "december")
    ])

    static let englishRules = rules(polish: false)
    static let polishRules = rules(polish: true)

    static func regex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            preconditionFailure("Invalid date grammar: \(error)")
        }
    }

    private static func normalisations(_ pairs: [(String, String)]) -> [Normalisation] {
        pairs.map { Normalisation(expression: regex(#"(?<![\p{L}\p{N}])(?:"# + $0.0
                                                    + #")(?![\p{L}\p{N}])"#), replacement: $0.1) }
    }

    private static func rules(polish: Bool) -> [Rule] {
        let prefix = polish ? #"(?:(?:w|we)\s+)?"# : ""
        let patterns: [(Kind, String)] = [
            (.recurrence, #"(?:every!?|after)\s+(?:(?:second|[0-9]+)\s+)?(?:last day|"# + weekday
                + #"|days?|weeks?|months?|years?)(?:\s+on\s+(?:last day|day\s+[0-9]+|"#
                + weekday + #"(?:\s*,\s*"# + weekday + #")*))?"#),
            (.relative, #"today|tomorrow|dayaftertomorrow|yesterday|day after tomorrow"#),
            (.offset, #"in\s+([0-9]+)\s+(days?|weeks?|months?|years?)"#),
            (.weekday, prefix + #"(?:(next)\s+)?("# + weekday + ")"),
            (.iso, #"([0-9]{4})-([0-9]{1,2})-([0-9]{1,2})"#),
            (.dayMonth, #"([0-9]{1,2})\s+("# + month + #")(?:\s+([0-9]{4}))?"#),
            (.monthDay, "(" + month + #")\s+([0-9]{1,2})(?:,?\s+([0-9]{4}))?"#),
            (.numeric, #"([0-9]{1,2})([/.])([0-9]{1,2})(?:[/.]([0-9]{4}))?"#)
        ]
        return patterns.map { Rule(kind: $0.0, expression: regex(
            #"(?<![\p{L}\p{N}/.:-])(?:"# + $0.1 + #")(?![\p{L}\p{N}/.:-])"#)) }
    }
}
