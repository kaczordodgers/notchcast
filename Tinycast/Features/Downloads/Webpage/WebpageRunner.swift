import Foundation

struct WebpageRunner: DownloadRunner {
    let kind = "webpage"
    let tools: [DownloadTool] = []

    func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? {
        try Task.checkCancellation()
        guard let source = URL(string: job.source) else { throw PublicWebAddress.Refusal.invalidURL }
        try PublicWebAddress.validate(source)
        return try await WebpageSaver(destination: context.destination).save(source)
    }
}
