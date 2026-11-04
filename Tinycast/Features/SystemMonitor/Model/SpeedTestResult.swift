import Foundation

nonisolated struct SpeedTestResult: Sendable, Equatable {
    struct Measurement: Sendable, Equatable {
        let throughputMbps: Double
        let responsivenessRPM: Double?
        let baseRTTMilliseconds: Double?
    }

    let downloadMbps: Double
    let uploadMbps: Double
    let responsivenessRPM: Double?
    let baseRTTMilliseconds: Double?

    static func parse(_ data: Data, phase: SpeedTestPhase) throws -> Measurement {
        let object = try JSONSerialization.jsonObject(with: data)
        let prefix = phase == .download ? "dl" : "ul"
        guard let values = object as? [String: Any],
              let throughput = number(values["\(prefix)_throughput"]) else {
            throw CocoaError(.coderInvalidValue)
        }
        return Measurement(throughputMbps: throughput / 1_000_000,
                           responsivenessRPM: number(values["\(prefix)_responsiveness"] ?? values["responsiveness"]),
                           baseRTTMilliseconds: number(values["base_rtt"]))
    }

    static func parse(_ data: Data) throws -> Self {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let values = object as? [String: Any],
              let down = number(values["dl_throughput"]),
              let up = number(values["ul_throughput"]) else { throw CocoaError(.coderInvalidValue) }
        return Self(downloadMbps: down / 1_000_000, uploadMbps: up / 1_000_000,
                    responsivenessRPM: number(values["responsiveness"]),
                    baseRTTMilliseconds: number(values["base_rtt"]))
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        let number = value.doubleValue
        return number.isFinite && number >= 0 ? number : nil
    }
}
