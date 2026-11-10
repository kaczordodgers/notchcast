import Foundation

/// Registers a runner with a different tool pre-check than the one it declares.
struct NotchcastDownloadRunner: DownloadRunner {
    let runner: any DownloadRunner
    let tools: [DownloadTool]
    var kind: String { runner.kind }

    init(_ runner: any DownloadRunner, tools: [DownloadTool]) {
        self.runner = runner
        self.tools = tools
    }

    func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? {
        try await runner.run(job, context: context)
    }
}
