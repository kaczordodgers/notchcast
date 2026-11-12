import Foundation

enum CommandProcessRunner {
    @concurrent
    static func run(_ request: CatalogShellCommandRunner.Request) async throws
        -> CatalogShellCommandRunner.Result
    {
        let result = try await ProcessRunner.run(.init(
            executable: URL(fileURLWithPath: request.executable), arguments: request.arguments,
            environment: DownloadToolLookup().environment,
            directory: request.workingDirectory.map { URL(fileURLWithPath: $0) },
            stderr: .capture(limit: Int.max), timeout: request.timeout,
            stopLadder: .terminating(grace: .milliseconds(250)), stopsGroup: true))
        return CatalogShellCommandRunner.Result(exitStatus: result.signaled ? 128 + result.status : result.status,
            standardOutput: tail(result.stdout), standardError: tail(result.stderr))
    }

    private static func tail(_ data: Data) -> Data {
        let bytes = data.suffix(65_536).drop(while: { $0 & 0xC0 == 0x80 })
        return Data((String(bytes: bytes, encoding: .utf8) ?? "").utf8)
    }
}
