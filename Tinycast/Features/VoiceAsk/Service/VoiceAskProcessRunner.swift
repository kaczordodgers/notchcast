import Foundation

@MainActor
enum VoiceAskProcessRunner {
    static func run(_ executable: URL, arguments: [String], input: Data,
                    timeout: Duration = .seconds(120)) async throws -> VoiceAskCLITransport.Output {
        let request = ProcessRunner.Request(
            executable: executable, arguments: arguments,
            environment: ExecutableLocator.environment(running: executable),
            input: input, stderr: .capture(limit: 500), timeout: timeout)
        do {
            let output = try await ProcessRunner.run(request)
            return .init(status: output.status, stdout: output.stdout, stderr: output.stderr)
        } catch ProcessRunner.Failure.timedOut {
            throw VoiceAskCLIError.timeout
        }
    }
}
