import Foundation

struct ChargeEngine: Sendable, Equatable, Codable {
    var heat = HeatProtection()
    var calibration = CalibrationSession()
    private(set) var decision = ChargePolicy.Decision.release

    mutating func evaluate(policy: ChargePolicy, percent: Int?, charging: Bool,
                           connected: Bool, celsius: Double?, now: Date, heatEnabled: Bool = false,
                           appleCalibration: Bool = false) -> ChargePolicy.Decision {
        guard policy.enabled else { decision = .release; return decision }
        guard connected, let percent, (0...100).contains(percent) else { return decision }
        if heat.paused(enabled: heatEnabled, celsius: celsius, now: now) {
            decision = .init(charging: false, adapter: true)
            return decision
        }
        if appleCalibration { decision = .release; return decision }
        calibration.advance(percent: percent, limit: policy.limit, connected: connected, now: now)
        decision = calibration.decision ?? policy.decide(percent: percent, charging: charging, connected: connected)
        return decision
    }
}
