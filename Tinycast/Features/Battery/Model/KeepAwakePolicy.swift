import Foundation

struct KeepAwakePolicy: Sendable, Equatable {
    enum Outcome: Sendable, Equatable { case off, expired, batteryFloor, locked, hold }
    var enabled = false
    var until: Date?
    var floor = 20
    var pauseWhenLocked = false
    var allowDisplaySleep = false

    func evaluate(now: Date, onBattery: Bool, percent: Int?, locked: Bool) -> Outcome {
        guard enabled else { return .off }
        if let until, now >= until { return .expired }
        if onBattery, floor > 0 {
            guard let percent, (0...100).contains(percent), percent > min(50, floor) else {
                return .batteryFloor
            }
        }
        if locked && pauseWhenLocked { return .locked }
        return .hold
    }

    var assertionTypes: [String] {
        allowDisplaySleep ? ["PreventUserIdleSystemSleep"]
            : ["PreventUserIdleSystemSleep", "PreventUserIdleDisplaySleep"]
    }
}
