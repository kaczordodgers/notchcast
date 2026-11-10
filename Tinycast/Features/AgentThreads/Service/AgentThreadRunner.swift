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
        let request = ProcessRunner.Request(
            executable: URL(filePath: path), arguments: arguments,
            environment: Self.environment(for: path, inheriting: ProcessInfo.processInfo.environment),
            timeout: timeout)
        let output: ProcessRunner.Output
        do { output = try await ProcessRunner.run(request) } catch ProcessRunner.Failure.timedOut {
            throw AgentThreadFailure.timeout
        }
        guard output.status == 0 else { throw AgentThreadFailure.commandFailed }
        return output.stdout
    }
}
