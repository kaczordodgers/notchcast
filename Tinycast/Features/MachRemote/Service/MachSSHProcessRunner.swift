import Foundation

enum MachSSHProcessRunner {
    @concurrent static func run(_ executable: String, _ arguments: [String]) async throws -> MachSSH.Result {
        try Task.checkCancellation()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        let output = try FileHandle(forWritingTo: url)
        defer { try? output.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        return try await withTaskCancellationHandler {
            let exit = try process.runObservingExit()
            if Task.isCancelled { process.terminate() }
            exit.wait()
            try Task.checkCancellation()
            return MachSSH.Result(status: process.terminationStatus,
                                  output: String(decoding: try Data(contentsOf: url), as: UTF8.self))
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}
