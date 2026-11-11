import Foundation

extension DownloadToolLookup: DownloadToolHost {
    func run(
        _ executable: URL, arguments: [String], workingDirectory: URL?,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> DownloadProcessResult {
        let result = try await ChildProcess(
            executable: executable, arguments: arguments, environment: environment,
            workingDirectory: workingDirectory).run(onLine: onLine)
        return DownloadProcessResult(status: result.status, output: result.output, errors: result.errors)
    }
}
