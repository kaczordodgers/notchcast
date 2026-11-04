import Foundation

enum CommandProcessRunner {
    @concurrent
    static func run(_ request: CatalogShellCommandRunner.Request) async throws
        -> CatalogShellCommandRunner.Result
    {
        let result = try await ChildProcess(
            executable: URL(fileURLWithPath: request.executable), arguments: request.arguments,
            workingDirectory: request.workingDirectory.map { URL(fileURLWithPath: $0) }).run()
        return CatalogShellCommandRunner.Result(exitStatus: result.status,
            standardOutput: Data(result.output.utf8), standardError: Data(result.errors.utf8))
    }
}
