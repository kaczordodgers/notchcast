import Foundation
import Observation

@MainActor
@Observable
final class DayMarketsStore {
    private(set) var quotes: [DayMarketQuote] = []
    private(set) var lastError: String?
    private(set) var symbols: [String]
    private let defaults: UserDefaults
    private let key = "notchcast.day.marketSymbols"
    private var visible = false
    private var lastAttempt: Date?
    private var fetching = false
    private var generation = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?

    convenience init() {
        self.init(defaults: DayStorage.defaults)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        symbols = defaults.stringArray(forKey: key) ?? ["USDPLN=X", "^GSPC", "BTC-USD"]
    }

    func setSymbols(_ symbols: [String]) {
        self.symbols = symbols.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        defaults.set(self.symbols, forKey: key)
        quotes = []
        generation = UUID()
    }

    func setVisible(_ visible: Bool) {
        self.visible = visible
        task?.cancel()
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
        guard visible, !fetching, lastAttempt.map({ now.timeIntervalSince($0) >= 60 }) ?? true else { return }
        lastAttempt = now
        fetching = true
        defer { fetching = false }
        let operation = generation
        var result: [DayMarketQuote] = []
        do {
            for symbol in symbols {
                var url = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/")!
                url.path += symbol
                url.queryItems = [.init(name: "range", value: "5d"), .init(name: "interval", value: "5m")]
                let quote = try DayMarketQuote.decode(await DayHTTPService.data(url.url!), symbol: symbol)
                guard !Task.isCancelled, visible, operation == generation else { return }
                result.append(quote)
            }
            quotes = result
            lastError = nil
        } catch {
            guard !Task.isCancelled, visible, operation == generation else { return }
            lastError = error.localizedDescription
        }
    }
}
