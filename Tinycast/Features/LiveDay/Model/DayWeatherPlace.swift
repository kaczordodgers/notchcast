import Foundation

struct DayWeatherPlace: Codable, Sendable, Equatable {
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?

    static func decodeCities(_ data: Data) throws -> [Self] {
        struct Reply: Decodable { let results: [DayWeatherPlace]? }
        return try JSONDecoder().decode(Reply.self, from: data).results ?? []
    }
}
