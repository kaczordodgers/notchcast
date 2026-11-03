import Foundation

enum BatteryRootVerbs: String, Sendable, CaseIterable {
    case chargingOn = "battery-charging-on"
    case chargingOff = "battery-charging-off"
    case adapterOn = "battery-adapter-on"
    case adapterOff = "battery-adapter-off"
    case sleepOn = "battery-sleep-on"
    case sleepOff = "battery-sleep-off"

    var command: [String] {
        switch self {
        case .sleepOn: ["/usr/bin/pmset", "-a", "disablesleep", "0"]
        case .sleepOff: ["/usr/bin/pmset", "-a", "disablesleep", "1"]
        default: []
        }
    }

    func writes(modern: Bool) -> [(key: String, bytes: [UInt8])] {
        switch self {
        case .chargingOn, .chargingOff:
            let off = self == .chargingOff
            return modern ? [("CHTE", [off ? 1 : 0, 0, 0, 0])]
                : [("CH0B", [off ? 2 : 0]), ("CH0C", [off ? 2 : 0])]
        case .adapterOn, .adapterOff:
            return [(modern ? "CHIE" : "CH0I", [self == .adapterOn ? 0 : (modern ? 8 : 1)])]
        default: return []
        }
    }
}
