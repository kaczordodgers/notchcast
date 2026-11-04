import Foundation

nonisolated struct MonitorAlertRule: Sendable, Equatable {
    enum Direction: Sendable, Equatable { case above, below }
    enum Result: Sendable, Equatable { case fire, none }
    enum Metric: Sendable, CaseIterable {
        case cpu, cpuTemperature, memoryPressure, diskFree, battery, batteryTemperature
    }

    let direction: Direction
    let threshold: Double
    let recoverValue: Double
    let sustainCount: Int
    let cooldown: TimeInterval
    private var consecutiveBreaches = 0
    private var active = false
    private var lastFire: Date?

    init(
        direction: Direction, threshold: Double, recoverValue: Double,
        sustainCount: Int = 3, cooldown: TimeInterval = 15 * 60
    ) {
        precondition(threshold.isFinite && recoverValue.isFinite)
        precondition(sustainCount > 0 && cooldown.isFinite && cooldown >= 0)
        precondition(direction == .above ? recoverValue <= threshold : recoverValue >= threshold)
        self.direction = direction
        self.threshold = threshold
        self.recoverValue = recoverValue
        self.sustainCount = sustainCount
        self.cooldown = cooldown
    }

    mutating func resetBreaches() { consecutiveBreaches = 0 }

    mutating func evaluate(_ value: Double, at now: Date) -> Result {
        guard value.isFinite else {
            consecutiveBreaches = 0
            return .none
        }
        if active {
            if direction == .above ? value <= recoverValue : value >= recoverValue {
                active = false
            }
            return .none
        }
        let breaches = direction == .above ? value > threshold : value < threshold
        consecutiveBreaches = breaches ? Swift.min(consecutiveBreaches + 1, sustainCount) : 0
        guard consecutiveBreaches == sustainCount,
              lastFire.map({ now.timeIntervalSince($0) >= cooldown }) ?? true else { return .none }
        active = true
        consecutiveBreaches = 0
        lastFire = now
        return .fire
    }

    // Memory pressure uses ordinal levels: normal = 0, warning = 1, critical = 2.
    static let defaults: [Metric: MonitorAlertRule] = [
        .cpu: .init(direction: .above, threshold: 90, recoverValue: 80),
        .cpuTemperature: .init(direction: .above, threshold: 90, recoverValue: 85),
        .memoryPressure: .init(direction: .above, threshold: 1, recoverValue: 0),
        .diskFree: .init(direction: .below, threshold: 10, recoverValue: 15),
        .battery: .init(direction: .below, threshold: 15, recoverValue: 20),
        .batteryTemperature: .init(direction: .above, threshold: 40, recoverValue: 35)
    ]
}
