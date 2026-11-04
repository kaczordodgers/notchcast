import Foundation

struct DownloadRunContext: Sendable {
    let destination: URL
    let tools: DownloadToolLookup
    private let progress: @MainActor @Sendable (DownloadProgress) -> Void
    private let detail: @MainActor @Sendable (String) -> Void
    let reportNetwork: @MainActor @Sendable (Bool) -> Void

    init(
        destination: URL, tools: DownloadToolLookup = DownloadToolLookup(),
        report: @escaping @MainActor @Sendable (DownloadProgress) -> Void = { _ in },
        detail: @escaping @MainActor @Sendable (String) -> Void = { _ in },
        reportNetwork: @escaping @MainActor @Sendable (Bool) -> Void = { _ in }
    ) {
        self.destination = destination
        self.tools = tools
        progress = report
        self.detail = detail
        self.reportNetwork = reportNetwork
    }

    @MainActor
    func report(_ value: DownloadProgress) {
        guard !Task.isCancelled else { return }
        progress(value)
    }

    func spawn(
        executable: URL, arguments: [String], workingDirectory: URL? = nil,
        onLine: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> ChildProcess.Result {
        let child = ChildProcess(
            executable: executable, arguments: arguments,
            environment: tools.environment, workingDirectory: workingDirectory)
        let result = try await child.run(onLine: onLine)
        try Task.checkCancellation()
        if let line = result.errors.split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespaces) }).last(where: { !$0.isEmpty }) {
            await detail(line)
        }
        guard result.status == 0 else { throw ChildProcess.Failure(result: result) }
        return result
    }
}
