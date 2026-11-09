import Foundation

struct NBPAnswerRates: Equatable, Sendable {
    enum Failure: Error { case invalidTable }

    let effectiveDate: String
    let rates: CurrencyRates

    private struct Table: Decodable {
        struct Rate: Decodable {
            let code: String
            let mid: Double
        }
        let effectiveDate: String
        let rates: [Rate]
    }

    static func decode(_ data: Data, fetchedAt: Date) throws -> Self {
        let tables = try JSONDecoder().decode([Table].self, from: data)
        guard tables.count == 1, let table = tables.first, !table.rates.isEmpty else {
            throw Failure.invalidTable
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: table.effectiveDate),
            formatter.string(from: date) == table.effectiveDate else { throw Failure.invalidTable }

        var quotes = ["PLN": 1.0]
        for rate in table.rates {
            guard rate.code.utf8.count == 3,
                rate.code.utf8.allSatisfy({ (65...90).contains($0) }),
                quotes[rate.code] == nil, rate.mid.isFinite, rate.mid > 0,
                (1 / rate.mid).isFinite else { throw Failure.invalidTable }
            quotes[rate.code] = 1 / rate.mid
        }
        return Self(
            effectiveDate: table.effectiveDate,
            rates: CurrencyRates(base: "PLN", rates: quotes, fetchedAt: fetchedAt))
    }
}
