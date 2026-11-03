import Foundation

nonisolated struct SpeedTestResult: Sendable, Equatable {
    let downloadMbps: Double
    let uploadMbps: Double
    let responsivenessRPM: Double?
    let baseRTTMilliseconds: Double?

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
