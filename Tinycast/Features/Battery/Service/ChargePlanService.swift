import Foundation

struct ChargePlanService: Sendable {
    func apply(_ decision: ChargePolicy.Decision, watchdogReady: Bool,
               run: (RootContract.Command) throws -> Void) throws {
        if decision.adapter { try run(.batteryAdapterOn) }
        try run(decision.charging && decision.adapter ? .batteryChargingOn : .batteryChargingOff)
        if !decision.adapter && watchdogReady { try run(.batteryAdapterOff) }
    }

    func release(run: (RootContract.Command) throws -> Void) throws {
        let adapter = Result { try run(.batteryAdapterOn) }
        let charging = Result { try run(.batteryChargingOn) }
        try adapter.get()
        try charging.get()
    }
}
