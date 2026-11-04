import Foundation

nonisolated enum MacSetupRootVerbs: String, CaseIterable, Sendable {
    case disableStandby, enableStandby, disableAutoPowerOff, enableAutoPowerOff

    var command: TweakCommand {
        let key: String
        let value: String
        switch self {
        case .disableStandby: (key, value) = ("standby", "0")
        case .enableStandby: (key, value) = ("standby", "1")
        case .disableAutoPowerOff: (key, value) = ("autopoweroff", "0")
        case .enableAutoPowerOff: (key, value) = ("autopoweroff", "1")
        }
        return TweakCommand(executable: "/usr/bin/pmset", arguments: ["-a", key, value])
    }
}
