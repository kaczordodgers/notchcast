import Foundation

nonisolated enum SystemToolsHelperPolicy {
    static func available(_ feature: NotchcastFeature) -> Bool {
        switch feature {
        case .sudoTouchID:
            RootContract.Command(rawValue: "sudo-touchid-on") != nil
                && RootContract.Command(rawValue: "sudo-touchid-off") != nil
        case .spotlightOff:
            RootContract.Command(rawValue: "spotlight-off") != nil
                && RootContract.Command(rawValue: "spotlight-on") != nil
        default: true
        }
    }
}
