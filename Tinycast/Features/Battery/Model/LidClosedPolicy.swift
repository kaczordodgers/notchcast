import Foundation

enum LidClosedPolicy {
    static func plan(enabled: Bool, helperReady: Bool, keepAwakeHolding: Bool) -> RootContract.Command {
        enabled && helperReady && keepAwakeHolding ? .batterySleepOff : .batterySleepOn
    }
}
