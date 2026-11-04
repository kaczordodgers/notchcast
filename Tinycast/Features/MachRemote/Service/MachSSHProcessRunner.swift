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
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                process.terminationHandler = { _ in continuation.resume() }
                do {
                    try process.run()
                    if Task.isCancelled { process.terminate() }
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
            try Task.checkCancellation()
            return MachSSH.Result(status: process.terminationStatus,
                                  output: String(bytes: try Data(contentsOf: url), encoding: .utf8) ?? "")
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}
