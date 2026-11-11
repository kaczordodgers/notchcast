import Foundation

enum Power {
    /// A fixed tool with an empty environment and no streams; a non-zero exit refuses the change.
    static func runTool(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
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
