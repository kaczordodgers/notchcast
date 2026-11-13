// notchcast-sources: Tinycast/Features/LiveDay/Model/DayMarketQuote.swift
// notchcast-sources: Tinycast/Features/LiveDay/Model/DayMarketsPolicy.swift
// notchcast-sources: Tinycast/Features/LiveDay/Service/DayMarketsStore.swift
import Foundation

@main
struct MarketCancellationTest {
    @MainActor static func main() async {
        let suite = "market-cancel-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["TEST"], forKey: DayMarketsStore.symbolsKey)
        var calls = 0
        var pending: CheckedContinuation<Data, any Error>?
        let store = DayMarketsStore(defaults: defaults, fetch: { _ in
            calls += 1
            if calls == 1 { return try await withCheckedThrowingContinuation { pending = $0 } }
            throw URLError(.notConnectedToInternet)
        })
        store.setVisible(true)
        while calls == 0 { await Task.yield() }
        store.setVisible(false)
        store.setVisible(true)
        for _ in 0..<100 { await Task.yield() }
        precondition(calls == 2, "Returning to Day retries an interrupted fetch immediately")
        pending?.resume(throwing: CancellationError())
        store.setVisible(false)
        print("PASS cancelled market fetch does not throttle the next visit")
    }
}

enum DayStorage {
    @MainActor static var defaults: UserDefaults { .standard }
}

enum DayHTTPService {
    static func data(_ url: URL) async throws -> Data { throw URLError(.unsupportedURL) }
}
