import Foundation

enum BatteryRootVerbs: String, Sendable, CaseIterable {
    case chargingOn = "battery-charging-on"
    case chargingOff = "battery-charging-off"
    case adapterOn = "battery-adapter-on"
    case adapterOff = "battery-adapter-off"
    case sleepOn = "battery-sleep-on"
    case sleepOff = "battery-sleep-off"

}
