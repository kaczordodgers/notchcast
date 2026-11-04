import Foundation

enum LidClosedPolicy {
    static func plan(enabled: Bool, helperReady: Bool, keepAwakeHolding: Bool) -> BatteryRootVerbs {
        enabled && helperReady && keepAwakeHolding ? .sleepOff : .sleepOn
    }
}
