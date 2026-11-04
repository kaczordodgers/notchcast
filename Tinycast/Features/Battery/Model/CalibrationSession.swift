import Foundation

struct CalibrationSession: Sendable, Equatable, Codable {
    enum Step: Int, Sendable, Codable {
        case chargeToFull = 1, drainToLow, chargeToFullAgain, returnToLimit
    }

    private(set) var step: Step?
    private(set) var completedAt: Date?

    mutating func start() { completedAt = nil; step = .chargeToFull }
    mutating func cancel() { step = nil }

    mutating func advance(percent: Int?, limit: Int, connected: Bool, now: Date) {
        guard connected, let percent, (0...100).contains(percent),
              ChargePolicy.limits.contains(limit), let step else { return }
        let reached: Bool
        switch step {
        case .chargeToFull, .chargeToFullAgain: reached = percent == 100
        case .drainToLow: reached = percent <= 10
        case .returnToLimit: reached = percent <= limit
        }
        guard reached else { return }
        self.step = Step(rawValue: step.rawValue + 1)
        if self.step == nil { completedAt = now }
    }

    var decision: ChargePolicy.Decision? {
        switch step {
        case .chargeToFull, .chargeToFullAgain: .release
        case .drainToLow, .returnToLimit: .init(charging: false, adapter: false)
        case nil: nil
        }
    }
}
