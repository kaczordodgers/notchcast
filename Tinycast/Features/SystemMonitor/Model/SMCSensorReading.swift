import Foundation

nonisolated struct SMCSensorReading: Sendable, Equatable {
    struct Fan: Sendable, Equatable {
        let index: Int
        let currentRPM: Double?
        let minimumRPM: Double?
        let maximumRPM: Double?
    }

    let cpuTemperature: Double?
    let gpuTemperature: Double?
    let systemPowerWatts: Double?
    let fans: [Fan]
    var maximumCPUTemperature: Double?

    static func fanRPM(_ value: Double?) -> Double? {
        value.flatMap { $0.isFinite && (0...30_000).contains($0) ? $0 : nil }
    }

    static func powerWatts(_ value: Double?) -> Double? {
        value.flatMap { $0.isFinite && (0...2_000).contains($0) ? $0 : nil }
    }
}
