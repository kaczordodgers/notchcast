import Foundation

struct DayMarketQuote: Sendable {
    let symbol: String
    let price: Double
    let change24Hours: Double?

    private struct Reply: Decodable {
        struct Chart: Decodable {
            struct Result: Decodable {
                struct Meta: Decodable { let regularMarketPrice: Double }
                struct Indicators: Decodable {
                    struct Quote: Decodable { let close: [Double?] }
                    let quote: [Quote]
                }
                let meta: Meta
                let timestamp: [Double]
                let indicators: Indicators
            }
            let result: [Result]?
        }
        let chart: Chart
    }

    static func decode(_ data: Data, symbol: String) throws -> Self {
        guard let result = try JSONDecoder().decode(Reply.self, from: data).chart.result?.first,
            let closes = result.indicators.quote.first?.close,
            closes.count == result.timestamp.count,
            result.meta.regularMarketPrice.isFinite
        else { throw URLError(.cannotParseResponse) }
        let points = zip(result.timestamp, closes).compactMap { time, price in
            price.flatMap { $0.isFinite ? (time: time, price: $0) : nil }
        }
        let target = (points.last?.time ?? 0) - 86400
        let reference = points.min { abs($0.time - target) < abs($1.time - target) }
            .flatMap { abs($0.time - target) <= 3600 && $0.price > 0 ? $0.price : nil }
        return Self(symbol: symbol, price: result.meta.regularMarketPrice,
                    change24Hours: reference.map { (result.meta.regularMarketPrice / $0 - 1) * 100 })
    }
}
