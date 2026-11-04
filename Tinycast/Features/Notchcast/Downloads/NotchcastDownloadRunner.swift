import Foundation

struct NotchcastDownloadRunner: DownloadRunner {
    let runner: any DownloadRunner
    let tools: [DownloadTool]
    let options: @MainActor @Sendable () -> [String: String]
    var kind: String { runner.kind }

    init(_ runner: any DownloadRunner, tools: [DownloadTool]? = nil,
         options: @escaping @MainActor @Sendable () -> [String: String]) {
        self.runner = runner
        self.tools = tools ?? runner.tools
        self.options = options
    }

    func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? {
        var job = job
        job.options.merge(await options()) { _, live in live }
        try Task.checkCancellation()
        return try await runner.run(job, context: context)
    }
}
