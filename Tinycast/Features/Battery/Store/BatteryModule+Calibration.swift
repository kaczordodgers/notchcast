import Foundation

extension BatteryModule {
    var calibrationGuidance: String? {
        switch calibrationStep {
        case .chargeToFull:
            String(localized: "Step 1 of 4: connect power and charge to 100%.", table: "Notchcast")
        case .drainToLow:
            String(localized: "Step 2 of 4: unplug to 10%, then reconnect.", table: "Notchcast")
        case .chargeToFullAgain:
            String(localized: "Step 3 of 4: keep power connected and charge to 100%.", table: "Notchcast")
        case .returnToLimit:
            String(localized: "Step 4 of 4: unplug to the saved charge limit, then reconnect.", table: "Notchcast")
        case nil: nil
        }
    }
}
