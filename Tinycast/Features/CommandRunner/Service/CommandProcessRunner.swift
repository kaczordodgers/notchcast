import Foundation

enum CommandProcessRunner {
    @concurrent
    static func run(_ request: CatalogShellCommandRunner.Request) async throws
        -> CatalogShellCommandRunner.Result
    {
        let executable = URL(fileURLWithPath: request.executable)
        var inherited = ProcessInfo.processInfo.environment.filter {
            ["TMPDIR", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY", "http_proxy", "https_proxy",
             "all_proxy", "no_proxy", "SSL_CERT_FILE", "SSL_CERT_DIR", "USER", "LOGNAME"].contains($0.key)
        }
        inherited["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        inherited["PATH"] = ExecutableLocator.searchDirectories().map(\.path).joined(separator: ":")
        do {
            let result = try await ProcessRunner.run(.init(
                executable: executable, arguments: request.arguments,
                environment: ExecutableLocator.environment(running: executable,
                    adding: ["LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8"], inherited: inherited),
                directory: request.workingDirectory.map { URL(fileURLWithPath: $0) },
                stderr: .capture(limit: 65_536), timeout: request.timeout,
                stopLadder: .terminating(grace: .milliseconds(250)), stopsGroup: true,
                outputTail: 65_536, groupCleanup: .keepAfterExit, killsOnQuit: true))
            return CatalogShellCommandRunner.Result(exitStatus: result.exitCode,
                standardOutput: Data((String(bytes: result.stdout, encoding: .utf8) ?? "").utf8),
                standardError: Data((String(bytes: result.stderr, encoding: .utf8) ?? "").utf8))
        } catch ProcessRunner.Failure.timedOut {
            return CatalogShellCommandRunner.Result(exitStatus: 143, standardOutput: Data(), standardError: Data())
        }
    }
}
