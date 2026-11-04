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

    @concurrent
    func run(arguments: [String]) async throws -> Data {
        guard let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw AgentThreadFailure.unavailable
        }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(filePath: path)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try Task.checkCancellation()
        try process.run()
        let reader = Task.detached { output.fileHandleForReading.readDataToEndOfFile() }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        do {
            while process.isRunning {
                try Task.checkCancellation()
                guard ContinuousClock.now < deadline else { throw AgentThreadFailure.timeout }
                try await Task.sleep(for: .milliseconds(25))
            }
        } catch {
            if process.isRunning { process.terminate() }
            reader.cancel()
            throw error
        }
        let data = await reader.value
        guard process.terminationStatus == 0 else { throw AgentThreadFailure.commandFailed }
        return data
    }
}
