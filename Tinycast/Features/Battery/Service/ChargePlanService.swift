import Foundation

struct ChargePlanService: Sendable {
    func apply(_ decision: ChargePolicy.Decision,
               run: (RootContract.Command) throws -> Void) throws {
        try run(.batteryAdapterOn)
        try run(decision.charging ? .batteryChargingOn : .batteryChargingOff)
    }

    func release(run: (RootContract.Command) throws -> Void) throws {
        let adapter = Result { try run(.batteryAdapterOn) }
        let charging = Result { try run(.batteryChargingOn) }
        try adapter.get()
        try charging.get()
    }
}
