import Foundation

struct TreadmillRecord: Codable, Equatable, Hashable, Sendable {
    let started: Double
    let ended: Double
    let seconds: Double
    let meters: Double
    let kcal: Double
    let steps: Double
    let averageKmh: Double
    var imported: Bool?

    enum CodingKeys: String, CodingKey {
        case started, ended, kcal, steps, imported
        case seconds = "duration_s", meters = "distance_m", averageKmh = "avg_kmh"
    }

    var isValid: Bool {
        [started, ended, seconds, meters, kcal, steps, averageKmh].allSatisfy {
            $0.isFinite && (0...253_402_300_799).contains($0)
        } && ended >= started
    }
}
