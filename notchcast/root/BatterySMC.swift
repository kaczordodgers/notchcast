import Foundation

enum BatterySMC {
    static func sleepArguments(_ command: RootContract.Command) -> [String]? {
        switch command {
        case .batterySleepOn: ["-a", "disablesleep", "0"]
        case .batterySleepOff: ["-a", "disablesleep", "1"]
        default: nil
        }
    }

    static func run(_ command: RootContract.Command) throws {
        if let arguments = sleepArguments(command) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
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
            return
        }
        try apply(command, smc: FanSMC.Connection())
    }

    static func apply(_ command: RootContract.Command, smc: any FanSMC.Access) throws {
        let candidates: [(String, [UInt8])]
        switch command {
        case .batteryChargingOn, .batteryChargingOff:
            let off = command == .batteryChargingOff
            candidates = [("CHTE", [off ? 1 : 0, 0, 0, 0]),
                          ("CH0B", [off ? 2 : 0]), ("CH0C", [off ? 2 : 0])]
        case .batteryAdapterOn, .batteryAdapterOff:
            let on = command == .batteryAdapterOn
            candidates = [("CHIE", [on ? 0 : 8]), ("CH0I", [on ? 0 : 1])]
        default: throw FanSMC.Failure.invalidValue
        }
        let writes = try candidates.compactMap { key, bytes -> (String, [UInt8])? in
            guard let info = try smc.info(key) else { return nil }
            guard info.size == bytes.count,
                  try smc.read(key, info: info).count == info.size else {
                throw FanSMC.Failure.invalidValue
            }
            return (key, bytes)
        }
        guard !writes.isEmpty else { throw FanSMC.Failure.unavailable }
        for (key, bytes) in writes { try smc.write(key, bytes: bytes) }
    }
}
