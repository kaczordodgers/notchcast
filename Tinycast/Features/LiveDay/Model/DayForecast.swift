import Foundation

struct DayForecast: Codable, Sendable {
    struct Hourly: Codable, Sendable {
        let time: [Double]
        let temperature_2m: [Double?]
        let weather_code: [Int?]
    }

    struct Daily: Codable, Sendable {
        let time: [Double]
        let temperature_2m_max: [Double?]
        let temperature_2m_min: [Double?]
        let weather_code: [Int?]
    }

    let timezone: String
    let hourly: Hourly
    let daily: Daily

    static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.hourly.time.count == value.hourly.temperature_2m.count,
            value.hourly.time.count == value.hourly.weather_code.count,
            value.daily.time.count == value.daily.temperature_2m_max.count,
            value.daily.time.count == value.daily.temperature_2m_min.count,
            value.daily.time.count == value.daily.weather_code.count
        else { throw URLError(.cannotParseResponse) }
        return value
    }
}
