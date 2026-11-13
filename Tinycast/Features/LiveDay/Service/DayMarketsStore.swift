import Foundation
import Observation

@MainActor
@Observable
final class DayMarketsStore {
    private(set) var quotes: [DayMarketQuote] = []
    private(set) var lastError: String?
    private(set) var failedSymbols: [String] = []
    private(set) var symbols: [String]
    private let defaults: UserDefaults
    @ObservationIgnored private let fetch: (URL) async throws -> Data
    nonisolated static let symbolsKey = "notchcast.day.marketSymbols"
    private var visible = false
    private var lastAttempt: Date?
    private var fetchingGeneration: UUID?
    private var generation = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?

    convenience init() {
        self.init(defaults: DayStorage.defaults)
    }

    init(defaults: UserDefaults, fetch: @escaping (URL) async throws -> Data = DayHTTPService.data) {
        self.defaults = defaults
        self.fetch = fetch
        symbols = defaults.stringArray(forKey: Self.symbolsKey) ?? ["USDPLN=X", "^GSPC", "BTC-USD"]
    }

    func setSymbols(_ symbols: [String]) {
        self.symbols = symbols.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        defaults.set(self.symbols, forKey: Self.symbolsKey)
        quotes = []
        failedSymbols = []
        lastError = nil
        lastAttempt = nil
        setVisible(visible)
    }

    func setVisible(_ visible: Bool) {
        self.visible = visible
        task?.cancel()
        if fetchingGeneration != nil { lastAttempt = nil }
        generation = UUID()
        task = nil
        guard visible else { return }
        task = Task { [weak self] in
            while !Task.isCancelled, self != nil {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(180))
            }
        }
    }

    func refresh() async {
        let now = Date()
        guard DayMarketsPolicy.canRefresh(visible: visible, fetching: fetchingGeneration == generation,
                                         lastAttempt: lastAttempt, now: now) else { return }
        lastAttempt = now
        let operation = generation
        fetchingGeneration = operation
        defer { if fetchingGeneration == operation { fetchingGeneration = nil } }
        var results: [Result<DayMarketQuote, Error>] = []
        let requestedSymbols = symbols
        for symbol in requestedSymbols {
            do {
                var url = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/")!
                url.path += symbol
                url.queryItems = [.init(name: "range", value: "5d"), .init(name: "interval", value: "5m")]
                let quote = try DayMarketQuote.decode(await fetch(url.url!), symbol: symbol)
                results.append(.success(quote))
            } catch {
                results.append(.failure(error))
            }
            guard DayMarketsPolicy.canApply(cancelled: Task.isCancelled, visible: visible,
                                            operation: operation, generation: generation) else { return }
        }
        guard DayMarketsPolicy.canApply(cancelled: Task.isCancelled, visible: visible,
                                        operation: operation, generation: generation) else { return }
        let merged = DayMarketsPolicy.merge(symbols: requestedSymbols, results: results)
        quotes = merged.quotes
        failedSymbols = merged.failedSymbols
        lastError = merged.error
    }
}
