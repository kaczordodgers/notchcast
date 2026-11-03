import Foundation

nonisolated enum SystemToolsHelperPolicy {
    static func available(_ feature: NotchcastFeature) -> Bool {
        switch feature {
        case .sudoTouchID:
            RootContract.Command(rawValue: TouchIDRootVerbs.enableSudoTouchID.rawValue) != nil
                && RootContract.Command(rawValue: TouchIDRootVerbs.disableSudoTouchID.rawValue) != nil
        case .spotlightOff:
            RootContract.Command(rawValue: SpotlightRootVerbs.turnOffIndexing.rawValue) != nil
        default: true
        }
    }
}
