import Foundation

@main
enum LiveDayTest {
    static func main() throws {
        let forecast = Data(#"""
        {"timezone":"Europe/Warsaw",
         "hourly":{"time":[0],"temperature_2m":[12],"weather_code":[0]},
         "daily":{"time":[0],"temperature_2m_max":[14],"temperature_2m_min":[6],"weather_code":[1]}}
        """#.utf8)
        let decoded = try DayForecast.decode(forecast)
        precondition(decoded.hourly.temperature_2m == [12])
        let cities = try DayWeatherPlace.decodeCities(Data(#"""
        {"results":[{"name":"Test","latitude":10,"longitude":20,"country":"Test Country"}]}
        """#.utf8))
        precondition(cities.first?.latitude == 10)
        let emptyCities = try DayWeatherPlace.decodeCities(Data("{}".utf8))
        precondition(emptyCities.isEmpty)
        let malformed = Data(#"""
        {"timezone":"UTC","hourly":{"time":[0],"temperature_2m":[],"weather_code":[0]},
         "daily":{"time":[],"temperature_2m_max":[],"temperature_2m_min":[],"weather_code":[]}}
        """#.utf8)
        precondition((try? DayForecast.decode(malformed)) == nil)
        let yahoo = Data(#"""
        {"chart":{"result":[{"meta":{"regularMarketPrice":110},"timestamp":[0,86400],
         "indicators":{"quote":[{"close":[100,110]}]}}]}}
        """#.utf8)
        let quote = try DayMarketQuote.decode(yahoo, symbol: "TEST")
        precondition(abs((quote.change24Hours ?? 0) - 10) < 0.001)
        let gap = Data(#"""
        {"chart":{"result":[{"meta":{"regularMarketPrice":110},"timestamp":[80000,86400],
         "indicators":{"quote":[{"close":[100,110]}]}}]}}
        """#.utf8)
        let gapQuote = try DayMarketQuote.decode(gap, symbol: "TEST")
        precondition(gapQuote.change24Hours == nil)
        let now = Date(timeIntervalSince1970: 100)
        precondition(DayMarketsPolicy.canRefresh(visible: true, fetching: false, lastAttempt: nil, now: now))
        for elapsed in [0.0, 59.999, 60, 180] {
            precondition(DayMarketsPolicy.canRefresh(visible: true, fetching: false,
                lastAttempt: now, now: now.addingTimeInterval(elapsed)) == (elapsed >= 60))
        }
        precondition(!DayMarketsPolicy.canRefresh(visible: false, fetching: false, lastAttempt: nil, now: now))
        precondition(!DayMarketsPolicy.canRefresh(visible: true, fetching: true, lastAttempt: nil, now: now))
        let operation = UUID()
        precondition(DayMarketsPolicy.canApply(cancelled: false, visible: true,
                                              operation: operation, generation: operation))
        precondition(!DayMarketsPolicy.canApply(cancelled: true, visible: true,
                                               operation: operation, generation: operation))
        precondition(!DayMarketsPolicy.canApply(cancelled: false, visible: false,
                                               operation: operation, generation: operation))
        precondition(!DayMarketsPolicy.canApply(cancelled: false, visible: true,
                                               operation: operation, generation: UUID()))
        let partial = DayMarketsPolicy.merge(symbols: ["BAD", "TEST", "BAD2"],
            results: [.failure(URLError(.badServerResponse)), .success(quote), .failure(URLError(.timedOut))])
        precondition(partial.quotes.map(\.symbol) == ["TEST"])
        precondition(partial.failedSymbols == ["BAD", "BAD2"] && partial.error != nil)
        let success = DayMarketsPolicy.merge(symbols: ["TEST"], results: [.success(quote)])
        precondition(success.quotes.count == 1 && success.failedSymbols.isEmpty && success.error == nil)
        let failure = DayMarketsPolicy.merge(symbols: ["BAD"], results: [.failure(URLError(.badServerResponse))])
        precondition(failure.quotes.isEmpty && failure.failedSymbols == ["BAD"] && failure.error != nil)
        let current = DayEvent(id: "a", title: "A", start: now.addingTimeInterval(-10),
                               end: now.addingTimeInterval(10), isAllDay: false, calendarID: "c")
        let next = DayEvent(id: "b", title: "B", start: now.addingTimeInterval(10),
                            end: now.addingTimeInterval(20), isAllDay: false, calendarID: "c")
        precondition(DayEvent.current(in: [next, current], now: now) == current)
        precondition(DayEvent.next(in: [next, current], now: now) == next)
        precondition(DayEvent.current(in: [current], now: current.end) == nil)
        print("LiveDay: decoding, market refresh gap, stale results, partial failures, event boundaries passed")
    }
}
