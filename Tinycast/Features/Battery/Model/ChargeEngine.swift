import Foundation

struct ChargeEngine: Sendable, Equatable, Codable {
    var heat = HeatProtection()
    var calibration = CalibrationSession()

    mutating func evaluate(policy: ChargePolicy, percent: Int?, charging: Bool,
                           connected: Bool, celsius: Double?, now: Date, heatEnabled: Bool = false,
                           appleCalibration: Bool = false) -> ChargePolicy.Decision {
        guard policy.enabled, connected, let percent, (0...100).contains(percent) else {
            return .release
        }
        if heat.paused(enabled: heatEnabled, celsius: celsius, now: now) {
            return .init(charging: false, adapter: true)
        }
        if appleCalibration { return .release }
        calibration.advance(percent: percent, limit: policy.limit, connected: connected, now: now)
        return calibration.decision ?? policy.decide(percent: percent, charging: charging, connected: connected)
    }
}
