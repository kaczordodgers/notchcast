import Foundation

struct WebpageSaver: Sendable {
    let destination: URL

    @MainActor
    func save(_ source: URL, saved: Date = .now) async throws -> URL {
        let article = try await WebpageExtractor().extract(source)
        try Task.checkCancellation()
        return try await write(article, saved: saved)
    }

    @concurrent
    func write(_ article: WebpageArticle, saved: Date) async throws -> URL {
        try Task.checkCancellation()
        let data = Data(article.markdown(saved: saved).utf8)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let stagingDirectory = destination.appendingPathComponent(".\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: stagingDirectory) }
        let staging = stagingDirectory.appendingPathComponent("article.md")
        try data.write(to: staging, options: .atomic)
        var number = 1
        while true {
            try Task.checkCancellation()
            let suffix = number == 1 ? "" : " (\(number))"
            let output = destination.appendingPathComponent("\(article.filename)\(suffix).md")
            do {
                do {
                    try FileManager.default.linkItem(at: staging, to: output)
                } catch CocoaError.fileWriteFileExists {
                    throw CocoaError(.fileWriteFileExists)
                } catch {
                    try FileManager.default.moveItem(at: staging, to: output)
                }
                return output
            } catch CocoaError.fileWriteFileExists {
                number += 1
            }
        }
    }
}
