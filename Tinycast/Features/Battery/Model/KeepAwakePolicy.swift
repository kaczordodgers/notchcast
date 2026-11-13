import Foundation

struct KeepAwakePolicy: Sendable, Equatable {
    enum Outcome: Sendable, Equatable { case off, expired, batteryFloor, hold }
    var enabled = false
    var until: Date?
    var floor = 20

    func evaluate(now: Date, onBattery: Bool, percent: Int?) -> Outcome {
        guard enabled else { return .off }
        if let until, now >= until { return .expired }
        if onBattery, floor > 0 {
            guard let percent, (0...100).contains(percent), percent > min(50, floor) else {
                return .batteryFloor
            }
        }
        return .hold
    }

    var assertionTypes: [String] {
        ["PreventUserIdleSystemSleep", "PreventUserIdleDisplaySleep"]
    }
}
