import Foundation

struct CurrencyAnswerQuery: Equatable, Sendable {
    let amount: Double
    let source: String
    let target: String

    static func parse(_ text: String) -> Self? {
        let words = text.lowercased().split(whereSeparator: \.isWhitespace)
        guard words.count == 2 || words.count == 4,
            let amount = Double(words[0].replacingOccurrences(of: ",", with: ".")),
            amount.isFinite,
            words[0].utf8.allSatisfy({ (48...57).contains($0) || [43, 45, 44, 46].contains($0) }),
            let source = code(words[1]) else { return nil }
        if words.count == 2 { return Self(amount: amount, source: source, target: "PLN") }
        guard words[2] == "to" || words[2] == "in", let target = code(words[3]) else { return nil }
        return Self(amount: amount, source: source, target: target)
    }

    private static func code(_ word: Substring) -> String? {
        let code = word.uppercased()
        return codes.contains(code) ? code : nil
    }

    private static let codes: Set<String> = [
        "PLN", "USD", "EUR", "GBP", "CHF", "JPY", "CZK", "DKK", "NOK", "SEK", "HUF", "RON",
        "TRY", "UAH", "ISK", "CAD", "AUD", "NZD", "HKD", "SGD", "THB", "ILS", "CLP", "PHP",
        "MXN", "ZAR", "BRL", "MYR", "IDR", "INR", "KRW", "CNY", "XDR",
    ]
}

struct LauncherCurrencyAnswer: Equatable, Sendable {
    let query: CurrencyAnswerQuery
    let converted: Double
    let effectiveDate: String
    let isStale: Bool

    func formattedValue(locale: Locale) -> String {
        converted.formatted(.number.locale(locale).precision(.fractionLength(2))) + " " + query.target
    }
}
