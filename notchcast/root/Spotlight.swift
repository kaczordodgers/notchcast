import Foundation

enum Spotlight {
    static func arguments(_ command: RootContract.Command) -> [String]? {
        switch command {
        case .spotlightOff: ["-a", "-i", "off"]
        case .spotlightOn: ["-a", "-i", "on"]
        default: nil
        }
    }

    static func run(_ command: RootContract.Command) throws {
        guard let arguments = arguments(command) else { throw FanSMC.Failure.invalidValue }
        try Power.runTool("/usr/bin/mdutil", arguments)
    }
}
