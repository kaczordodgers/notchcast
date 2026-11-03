import Foundation

struct ChargePlanService: Sendable {
    enum Failure: Error { case watchdogRequired }

    func apply(_ decision: ChargePolicy.Decision, watchdogReady: Bool,
               run: (BatteryRootVerbs) throws -> Void) throws {
        guard decision.adapter || watchdogReady else { throw Failure.watchdogRequired }
        do {
            if decision.adapter { try run(.adapterOn) }
            try run(decision.charging ? .chargingOn : .chargingOff)
            if !decision.adapter { try run(.adapterOff) }
        } catch {
            let original = error
            let adapter = Result { try run(.adapterOn) }
            let charging = Result { try run(.chargingOn) }
            try adapter.get()
            try charging.get()
            throw original
        }
    }

    func release(run: (BatteryRootVerbs) throws -> Void) throws {
        let adapter = Result { try run(.adapterOn) }
        let charging = Result { try run(.chargingOn) }
        try adapter.get()
        try charging.get()
    }
}
