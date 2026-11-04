import Foundation

enum MarkdownQuickLookReader {
    @concurrent
    static func read(_ url: URL) async throws -> MarkdownQuickLookDocument {
        try Task.checkCancellation()
        guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { throw CocoaError(.fileReadUnknown) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= MarkdownQuickLookDocument.maximumBytes {
            try Task.checkCancellation()
            let remaining = MarkdownQuickLookDocument.maximumBytes + 1 - data.count
            guard let chunk = try handle.read(upToCount: min(65_536, remaining)), !chunk.isEmpty else {
                break
            }
            data.append(chunk)
        }
        try Task.checkCancellation()
        return try MarkdownQuickLookDocument(data: data)
    }
}
