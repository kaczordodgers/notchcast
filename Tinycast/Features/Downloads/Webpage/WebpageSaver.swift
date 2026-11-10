import Foundation

struct WebpageSaver: Sendable {
    let destination: URL

    @MainActor
    func save(_ source: URL, saved: Date = .now) async throws -> URL {
        let article = if let api = XPost.apiURL(source) {
            try await XPost.fetch(source, from: api)
        } else {
            try await WebpageExtractor().extract(source)
        }
        try Task.checkCancellation()
        return try await write(article, saved: saved)
    }

    @concurrent
    func write(_ article: WebpageArticle, saved: Date) async throws -> URL {
        try Task.checkCancellation()
        return try JobOutput.publish(Data(article.markdown(saved: saved).utf8), in: destination,
                                     stem: article.filename, suffix: ".md")
    }
}
