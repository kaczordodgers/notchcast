import Foundation

enum BatteryRootVerbs: String, Sendable, CaseIterable {
    case chargeLimit60 = "charge-limit-60"
    case chargeLimit70 = "charge-limit-70"
    case chargeLimit80 = "charge-limit-80"
    case chargeLimit90 = "charge-limit-90"
    case chargeLimitOff = "charge-limit-off"
    case chargingOn = "battery-charging-on"
    case chargingOff = "battery-charging-off"
    case adapterOn = "battery-adapter-on"
    case adapterOff = "battery-adapter-off"
    case sleepOn = "battery-sleep-on"
    case sleepOff = "battery-sleep-off"

}
