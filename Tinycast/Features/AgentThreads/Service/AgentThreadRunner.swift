import Foundation

protocol AgentThreadRunning: Sendable {
    func run(arguments: [String]) async throws -> Data
}

enum AgentThreadFailure: Error, Equatable {
    case unavailable
    case timeout
    case commandFailed
}

struct AgentThreadRunner: AgentThreadRunning {
    var paths: [String] = ["/opt/homebrew/bin/t3", "/usr/local/bin/t3"]
    var timeout: Duration = .seconds(10)

    static func environment(for path: String, inheriting environment: [String: String]) -> [String: String] {
        var environment = environment
        environment["PATH"] = URL(filePath: path).deletingLastPathComponent().path + ":/usr/bin:/bin"
        return environment
    }

    @concurrent
    func run(arguments: [String]) async throws -> Data {
        guard let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw AgentThreadFailure.unavailable
        }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(filePath: path)
        process.arguments = arguments
        process.environment = Self.environment(for: path, inheriting: ProcessInfo.processInfo.environment)
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try Task.checkCancellation()
        let exit = try process.runObservingExit()
        let reader = Task.detached { output.fileHandleForReading.readDataToEndOfFile() }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        let timer = Task {
            do { try await Task.sleep(until: deadline) } catch { return }
            if process.isRunning { process.terminate() }
        }
        defer { timer.cancel() }
        await withTaskCancellationHandler {
            await Task.detached { exit.wait() }.value
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        let data = await reader.value
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw AgentThreadFailure.timeout }
        guard process.terminationStatus == 0 else { throw AgentThreadFailure.commandFailed }
        return data
    }
}
