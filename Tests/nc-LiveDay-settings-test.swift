import Foundation

@main
struct DaySettingsTest {
    @MainActor static func main() {
        let suite = "day-settings-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let weather = DayWeatherStore(defaults: defaults, cacheURL: cache)
        precondition(weather.place == nil && !weather.isRunning)
        let place = DayWeatherPlace(name: "Warsaw", latitude: 52.23, longitude: 21.01, country: "Poland")
        weather.select(place)
        precondition(weather.place == place && !weather.isRunning)
        let restored = DayWeatherStore(defaults: defaults, cacheURL: cache)
        precondition(restored.place == place && !restored.isRunning)
        restored.select(nil)
        precondition(restored.place == nil && !restored.isRunning)
        let markets = DayMarketsStore(defaults: defaults)
        precondition(markets.symbols == ["USDPLN=X", "^GSPC", "BTC-USD"])
        markets.setSymbols(["AAPL", "", "^GSPC"])
        precondition(DayMarketsStore(defaults: defaults).symbols == ["AAPL", "^GSPC"])
        precondition(markets.quotes.isEmpty)
        print("PASS Day settings persist without starting hidden weather or markets polling")
    }
}
