import Foundation

/// What a job run needs from its host. Downloads supplies it, so the job contract does not import Downloads.
protocol DownloadToolHost: Sendable {
    func find(_ tool: DownloadTool) -> URL?
    func run(
        _ executable: URL, arguments: [String], workingDirectory: URL?,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> DownloadProcessResult
}

struct DownloadProcessResult: Sendable, Equatable {
    let status: Int32
    let output: String
    let errors: String
}

struct DownloadProcessFailure: LocalizedError {
    let result: DownloadProcessResult

    var errorDescription: String? {
        result.errors.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.last { !$0.isEmpty }
            ?? String(localized: "Tool exited with status \(result.status).", table: "Notchcast")
    }
}

struct DownloadRunContext: Sendable {
    let destination: URL
    let tools: any DownloadToolHost
    private let progress: @MainActor @Sendable (DownloadProgress) -> Void
    private let detail: @MainActor @Sendable (String) -> Void

    init(
        destination: URL, tools: any DownloadToolHost,
        report: @escaping @MainActor @Sendable (DownloadProgress) -> Void = { _ in },
        detail: @escaping @MainActor @Sendable (String) -> Void = { _ in }
    ) {
        self.destination = destination
        self.tools = tools
        progress = report
        self.detail = detail
    }

    @MainActor
    func report(_ value: DownloadProgress) {
        guard !Task.isCancelled else { return }
        progress(value)
    }

    func spawn(
        executable: URL, arguments: [String], workingDirectory: URL? = nil,
        onLine: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> DownloadProcessResult {
        let result = try await tools.run(
            executable, arguments: arguments, workingDirectory: workingDirectory, onLine: onLine)
        try Task.checkCancellation()
        if let line = result.errors.split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespaces) }).last(where: { !$0.isEmpty }) {
            await detail(line)
        }
        guard result.status == 0 else { throw DownloadProcessFailure(result: result) }
        return result
    }
}
