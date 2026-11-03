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
        let current = DayEvent(id: "a", title: "A", start: now.addingTimeInterval(-10),
                               end: now.addingTimeInterval(10), isAllDay: false, calendarID: "c")
        let next = DayEvent(id: "b", title: "B", start: now.addingTimeInterval(10),
                            end: now.addingTimeInterval(20), isAllDay: false, calendarID: "c")
        precondition(DayEvent.current(in: [next, current], now: now) == current)
        precondition(DayEvent.next(in: [next, current], now: now) == next)
        precondition(DayEvent.current(in: [current], now: current.end) == nil)
        print("LiveDay: forecast, malformed arrays, Yahoo 24h/gap, event boundaries passed")
    }
}
