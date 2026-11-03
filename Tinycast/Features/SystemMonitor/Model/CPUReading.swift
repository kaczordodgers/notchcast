import Foundation

nonisolated struct CPUReading: Sendable, Equatable {
    struct Usage: Sendable, Equatable {
        let totalPercent: Double
        let userPercent: Double
        let systemPercent: Double
    }

    struct LoadAverage: Sendable, Equatable {
        let oneMinute: Double
        let fiveMinutes: Double
        let fifteenMinutes: Double
    }

    let usage: Usage?
    let cores: [Usage?]
    let loadAverage: LoadAverage?
}
