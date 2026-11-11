import Foundation

nonisolated struct DistillConvertRunner: DownloadRunner {
    typealias HTML = @Sendable (String, URL?, DownloadRunContext) async throws -> DistillConversion
    typealias Media = @Sendable (URL, DownloadRunContext) async throws -> DistillConversion

    static let kind = "convert"
    var kind: String { Self.kind }
    let tools: [DownloadTool] = []
    var html: HTML?
    var media: Media?
    var trash: DistillConverter.Trash = {
        try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
    }

    @concurrent
    func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? {
        guard job.source.hasPrefix("/") else { throw DistillConversion.Failure.unsafePath }
        let source = URL(fileURLWithPath: job.source)
        var converter = DistillConverter(trash: trash)
        if let html {
            converter.html = { text, base in try await html(text, base, context) }
        }
        if let media {
            converter.media = { url in try await media(url, context) }
        }
        let results = try await converter.convert(folder: source) { result in
            await context.report(DownloadProgress(stage: Self.detail(result)))
        }
        try Task.checkCancellation()
        if results.contains(where: { if case .failed = $0.status { return true }; return false }) {
            throw NSError(domain: "DistillConvert", code: 1, userInfo: [
                NSLocalizedDescriptionKey: results.map(Self.detail).joined(separator: "\n")
            ])
        }
        return results.first(where: { $0.output != nil })?.output
    }

    private static func detail(_ result: DistillConversion.Result) -> String {
        let message: String
        switch result.status {
        case .converted: message = String(localized: "Converted", table: "Notchcast")
        case .retained: message = String(localized: "Converted; original retained", table: "Notchcast")
        case .failed(let reason): message = reason
        case .skipped(let reason):
            switch reason {
            case .htmlUnavailable: message = String(localized: "Skipped: HTML converter is unavailable", table: "Notchcast")
            case .mediaUnavailable: message = String(localized: "Skipped: transcriber is unavailable", table: "Notchcast")
            case .markdown: message = String(localized: "Skipped: already Markdown", table: "Notchcast")
            case .generated: message = String(localized: "Skipped: generated file", table: "Notchcast")
            case .symbolicLink: message = String(localized: "Skipped: symbolic link", table: "Notchcast")
            case .unsupported: message = String(localized: "Skipped: unsupported format", table: "Notchcast")
            }
        }
        return result.source.lastPathComponent + ": " + message
    }
}
