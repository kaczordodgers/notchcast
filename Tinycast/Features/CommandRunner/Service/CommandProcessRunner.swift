import Foundation

enum CommandProcessRunner {
    @concurrent
    static func run(_ request: CatalogShellCommandRunner.Request) async throws
        -> CatalogShellCommandRunner.Result
    {
        do {
            let result = try await ProcessRunner.run(.init(
                executable: URL(fileURLWithPath: request.executable), arguments: request.arguments,
                environment: DownloadToolLookup().environment,
                directory: request.workingDirectory.map { URL(fileURLWithPath: $0) },
                stderr: .capture(limit: 65_536), timeout: request.timeout,
                stopLadder: .terminating(grace: .milliseconds(250)), stopsGroup: true,
                outputTail: 65_536, killsOnQuit: true))
            return CatalogShellCommandRunner.Result(exitStatus: result.signaled ? 128 + result.status : result.status,
                standardOutput: Data((String(bytes: result.stdout, encoding: .utf8) ?? "").utf8),
                standardError: Data((String(bytes: result.stderr, encoding: .utf8) ?? "").utf8))
        } catch ProcessRunner.Failure.timedOut {
            return CatalogShellCommandRunner.Result(exitStatus: 143, standardOutput: Data(), standardError: Data())
        }
    }
}
