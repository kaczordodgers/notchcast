import Foundation

extension DownloadToolLookup: DownloadToolHost {
    func run(
        _ executable: URL, arguments: [String], workingDirectory: URL?,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> DownloadProcessResult {
        try await ChildProcess(
            executable: executable, arguments: arguments, environment: environment,
            workingDirectory: workingDirectory).run(onLine: onLine)
    }
}
