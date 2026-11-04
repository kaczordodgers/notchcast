import Foundation

struct ChargePlanService: Sendable {
    func apply(_ decision: ChargePolicy.Decision, watchdogReady: Bool,
               run: (BatteryRootVerbs) throws -> Void) throws {
        if decision.adapter { try run(.adapterOn) }
        try run(decision.charging && decision.adapter ? .chargingOn : .chargingOff)
        if !decision.adapter && watchdogReady { try run(.adapterOff) }
    }

    func release(run: (BatteryRootVerbs) throws -> Void) throws {
        let adapter = Result { try run(.adapterOn) }
        let charging = Result { try run(.chargingOn) }
        try adapter.get()
        try charging.get()
    }
}
