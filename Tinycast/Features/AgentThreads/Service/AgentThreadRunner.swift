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
    var locate: @Sendable () -> URL? = { ExecutableLocator.find("t3") }
    var timeout: Duration = .seconds(10)

    @concurrent
    func run(arguments: [String]) async throws -> Data {
        guard let executable = locate() else { throw AgentThreadFailure.unavailable }
        let request = ProcessRunner.Request(
            executable: executable, arguments: arguments,
            environment: ExecutableLocator.environment(running: executable), timeout: timeout)
        let output: ProcessRunner.Output
        do { output = try await ProcessRunner.run(request) } catch ProcessRunner.Failure.timedOut {
            throw AgentThreadFailure.timeout
        }
        guard output.status == 0 else { throw AgentThreadFailure.commandFailed }
        return output.stdout
    }
}
