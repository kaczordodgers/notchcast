import Foundation

struct ShortenLinkService: Sendable {
    enum Failure: Error, Equatable { case noLink, unavailable }
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, Int)

    private let fetch: Fetch

    init(fetch: @escaping Fetch = Self.fetch) {
        self.fetch = fetch
    }

    static func pick(argument: String, frontAddress: String?, clipboard: String?) -> String? {
        let typed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return firstLink(in: typed) }
        return frontAddress.flatMap(firstLink) ?? clipboard.flatMap(firstLink)
    }

    func shorten(_ address: String) async throws -> String {
        try Task.checkCancellation()
        guard let link = CopyPathEngine.cleanLink(address),
            !link.contains(where: \.isWhitespace) else { throw Failure.noLink }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encoded = link.addingPercentEncoding(withAllowedCharacters: allowed),
            let url = URL(string: "https://tinyurl.com/api-create.php?url=" + encoded) else { throw Failure.noLink }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (body, status) = try await fetch(request)
        try Task.checkCancellation()
        guard status == 200, let text = String(data: body, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.contains(where: \.isWhitespace),
            let parts = URLComponents(string: text), parts.scheme == "https",
            parts.host?.lowercased() == "tinyurl.com", parts.user == nil, parts.password == nil,
            parts.port == nil, !parts.path.isEmpty, parts.path != "/" else { throw Failure.unavailable }
        return text
    }

    private static func firstLink(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let url = match.url, let clean = CopyPathEngine.cleanLink(url.absoluteString) { return clean }
        }
        return nil
    }

    private static func fetch(_ request: URLRequest) async throws -> (Data, Int) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
