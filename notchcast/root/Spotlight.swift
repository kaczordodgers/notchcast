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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdutil")
        process.arguments = arguments
        process.environment = [:]
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        finished.wait()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw FanSMC.Failure.refused
        }
    }
}
