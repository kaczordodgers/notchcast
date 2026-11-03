import Foundation

enum DayMarketsPolicy {
    static func canRefresh(visible: Bool, fetching: Bool, lastAttempt: Date?, now: Date) -> Bool {
        visible && !fetching && (lastAttempt.map { now.timeIntervalSince($0) >= 60 } ?? true)
    }

    static func canApply(cancelled: Bool, visible: Bool, operation: UUID, generation: UUID) -> Bool {
        !cancelled && visible && operation == generation
    }

    static func merge(symbols: [String], results: [Result<DayMarketQuote, Error>])
        -> (quotes: [DayMarketQuote], failedSymbols: [String], error: String?) {
        var quotes: [DayMarketQuote] = []
        var failedSymbols: [String] = []
        var error: String?
        for (symbol, result) in zip(symbols, results) {
            switch result {
            case .success(let quote): quotes.append(quote)
            case .failure(let failure):
                failedSymbols.append(symbol)
                error = failure.localizedDescription
            }
        }
        return (quotes, failedSymbols, error)
    }
}
