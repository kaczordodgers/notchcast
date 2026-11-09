import Foundation

/// X shows posts only behind a login, so they are read from the public fxtwitter mirror instead.
enum XPost {
    enum Failure: LocalizedError {
        case unavailable(Int), missing

        var errorDescription: String? {
            switch self {
            case .unavailable(let status):
                String(localized: "X returned HTTP status \(status) for this post.", table: "Notchcast")
            case .missing: String(localized: "X returned no readable post for this link.", table: "Notchcast")
            }
        }
    }

    typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// Cacheless, never `URLSession.shared`, so the saved Markdown stays the only copy.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    static func apiURL(_ source: URL) -> URL? {
        guard let scheme = source.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = source.host(percentEncoded: false)?.lowercased().replacing(/^(www|mobile)\./, with: ""),
              ["x.com", "twitter.com"].contains(host) else { return nil }
        let parts = source.pathComponents.filter { $0 != "/" }
        // x.com/i/article/<id> carries an article id, not the status id fxtwitter needs.
        guard parts.count >= 3, ["status", "article"].contains(parts[1]),
              parts[0].lowercased() != "i" || parts[1] == "status",
              parts[0].wholeMatch(of: /[A-Za-z0-9_]{1,15}/) != nil, parts[2].wholeMatch(of: /[0-9]{1,20}/) != nil
        else { return nil }
        return URL(string: "https://api.fxtwitter.com/\(parts[0])/status/\(parts[2])")
    }

    @concurrent
    static func fetch(_ source: URL, from api: URL,
                      load: Loader = { try await session.data(for: $0) }) async throws -> WebpageArticle {
        let (data, response) = try await load(URLRequest(url: api, timeoutInterval: 20))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { throw Failure.missing }
        guard status == 200 else { throw Failure.unavailable(status) }
        return try article(data, source: source)
    }

    static func article(_ data: Data, source: URL) throws -> WebpageArticle {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let tweet = (try? decoder.decode(Response.self, from: data))?.tweet else { throw Failure.missing }
        let author = tweet.author?.name ?? tweet.author?.screenName ?? "X"
        let published = tweet.createdTimestamp.map { Date(timeIntervalSince1970: $0).formatted(.iso8601) }
        if let article = tweet.article, case let body = html(of: article), !body.isEmpty {
            return WebpageArticle(title: article.title ?? title(of: tweet), author: author, published: published,
                                  source: source, baseURL: source, html: body)
        }
        var html = paragraphs(tweet.text) + media(tweet.media)
        if let quote = tweet.quote {
            let name = escape(quote.author?.name ?? quote.url ?? "")
            let heading = quote.url.map { "<a href=\"\(escape($0))\">\(name)</a>" } ?? name
            html += "<blockquote><p>\(heading)</p>\(paragraphs(quote.text))\(media(quote.media))</blockquote>"
        }
        guard !html.isEmpty else { throw Failure.missing }
        return WebpageArticle(title: title(of: tweet), author: author, published: published,
                              source: source, baseURL: source, html: html)
    }

    static func title(of tweet: Tweet) -> String {
        let line = (tweet.text ?? "").split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        guard !line.isEmpty else { return "Post \(tweet.id ?? "")" }
        guard line.count > 80 else { return line }
        let cut = line.prefix(80)
        return String(cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut) + "…"
    }

    private static func html(of article: Article) -> String {
        let entities = Dictionary((article.content?.entityMap ?? []).map { ($0.key, $0.value) }) { first, _ in first }
        let images = Dictionary((article.mediaEntities ?? []).compactMap { entry in
            entry.mediaInfo?.originalImgUrl.map { (entry.mediaId ?? "", $0) }
        }) { first, _ in first }
        var html = ""
        var openList: String?
        for block in article.content?.blocks ?? [] {
            let list = ["unordered-list-item": "ul", "ordered-list-item": "ol"][block.type ?? ""]
            if openList != list {
                if let openList { html += "</\(openList)>" }
                if let list { html += "<\(list)>" }
                openList = list
            }
            let text = block.text ?? ""
            switch block.type {
            case "header-one": html += "<h2>\(escape(text))</h2>"
            case "header-two": html += "<h3>\(escape(text))</h3>"
            case "header-three": html += "<h4>\(escape(text))</h4>"
            case "unordered-list-item", "ordered-list-item": html += "<li>\(inline(block, entities))</li>"
            case "blockquote": html += "<blockquote><p>\(inline(block, entities))</p></blockquote>"
            case "code-block": html += "<pre><code>\(escape(text))</code></pre>"
            case "atomic": html += atomic(block, entities, images)
            default: html += "<p>\(inline(block, entities))</p>"
            }
        }
        if let openList { html += "</\(openList)>" }
        return html
    }

    private static func atomic(_ block: Block, _ entities: [String: Entity], _ images: [String: String]) -> String {
        let entity = block.entityRanges?.first.flatMap { entities[String($0.key)] }
        let data = entity?.data
        switch entity?.type {
        case "MEDIA":
            let alt = escape(data?.caption?.trimmingCharacters(in: .whitespaces) ?? "")
            return (data?.mediaItems ?? []).compactMap { $0.mediaId.flatMap { images[$0] } }
                .map { "<p><img alt=\"\(alt)\" src=\"\(escape($0))\"></p>" }.joined()
        case "DIVIDER": return "<hr>"
        case "TWEET":
            guard let id = data?.tweetId else { return "" }
            return "<p><a href=\"https://x.com/i/status/\(escape(id))\">https://x.com/i/status/\(escape(id))</a></p>"
        case "MARKDOWN": return code(data?.markdown ?? "")
        default: return paragraphs(block.text)
        }
    }

    private static func code(_ markdown: String) -> String {
        var lines = markdown.components(separatedBy: "\n")
        guard let first = lines.first, first.hasPrefix("```"), lines.count > 1 else { return paragraphs(markdown) }
        let language = escape(String(first.drop { $0 == "`" }).trimmingCharacters(in: .whitespaces))
        lines.removeFirst()
        if lines.last?.hasPrefix("```") == true { lines.removeLast() }
        let label = language.isEmpty ? "" : " class=\"language-\(language)\""
        return "<pre><code\(label)>\(escape(lines.joined(separator: "\n")))</code></pre>"
    }

    private static func inline(_ block: Block, _ entities: [String: Entity]) -> String {
        let units = Array((block.text ?? "").utf16)
        var bold = [Bool](repeating: false, count: units.count)
        var italic = bold
        var links = [String?](repeating: nil, count: units.count)
        for range in block.inlineStyleRanges ?? [] {
            for index in clamped(range.offset, range.length, units.count) {
                if range.style == "Bold" { bold[index] = true }
                if range.style == "Italic" { italic[index] = true }
            }
        }
        for range in block.entityRanges ?? [] {
            guard let entity = entities[String(range.key)], entity.type == "LINK", let url = entity.data?.url else { continue }
            for index in clamped(range.offset, range.length, units.count) { links[index] = url }
        }
        var html = ""
        var start = 0
        while start < units.count {
            var end = start + 1
            while end < units.count, bold[end] == bold[start], italic[end] == italic[start], links[end] == links[start] {
                end += 1
            }
            let run = String(decoding: units[start..<end], as: UTF16.self)
            let body = run.trimmingCharacters(in: .whitespacesAndNewlines)
            var wrapped = lines(body)
            if italic[start] { wrapped = "<em>\(wrapped)</em>" }
            if bold[start] { wrapped = "<strong>\(wrapped)</strong>" }
            if let url = links[start] { wrapped = "<a href=\"\(escape(url))\">\(wrapped)</a>" }
            if body.isEmpty { wrapped = lines(run) } else if let range = run.range(of: body) {
                wrapped = lines(String(run[..<range.lowerBound])) + wrapped + lines(String(run[range.upperBound...]))
            }
            html += wrapped
            start = end
        }
        return html
    }

    private static func clamped(_ offset: Int, _ length: Int, _ count: Int) -> Range<Int> {
        let lower = min(max(offset, 0), count)
        return lower..<min(max(lower, offset + length), count)
    }

    private static func paragraphs(_ text: String?) -> String {
        (text ?? "").components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.map { "<p>\(lines($0))</p>" }.joined()
    }

    private static func media(_ media: Media?) -> String {
        (media?.all ?? []).compactMap { item in
            guard let url = item.url.map(escape) else { return nil }
            return item.type == "photo" ? "<p><img src=\"\(url)\"></p>" : "<p><a href=\"\(url)\">\(url)</a></p>"
        }.joined()
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Newlines become `<br>` because the Markdown converter collapses whitespace in text.
    private static func lines(_ text: String) -> String {
        escape(text).replacingOccurrences(of: "\n", with: "<br>")
    }

    private struct Response: Decodable { let tweet: Tweet? }

    struct Tweet: Decodable {
        let id: String?
        let text: String?
        let createdTimestamp: Double?
        let author: Author?
        let article: Article?
        let media: Media?
        let quote: Quote?
    }

    struct Quote: Decodable {
        let text: String?
        let url: String?
        let author: Author?
        let media: Media?
    }

    struct Author: Decodable {
        let name: String?
        let screenName: String?
    }

    struct Media: Decodable {
        struct Item: Decodable { let type: String?, url: String? }
        let all: [Item]?
    }

    struct Article: Decodable {
        struct Content: Decodable {
            struct Entry: Decodable { let key: String, value: Entity }
            let blocks: [Block]?
            let entityMap: [Entry]?
        }
        struct MediaEntity: Decodable {
            struct Info: Decodable { let originalImgUrl: String? }
            let mediaId: String?
            let mediaInfo: Info?
        }
        let title: String?
        let content: Content?
        let mediaEntities: [MediaEntity]?
    }

    struct Block: Decodable {
        struct Style: Decodable { let offset: Int, length: Int, style: String }
        struct EntityRange: Decodable { let key: Int, offset: Int, length: Int }
        let type: String?
        let text: String?
        let inlineStyleRanges: [Style]?
        let entityRanges: [EntityRange]?
    }

    struct Entity: Decodable {
        struct Item: Decodable { let mediaId: String? }
        struct Payload: Decodable {
            let url: String?
            let markdown: String?
            let tweetId: String?
            let caption: String?
            let mediaItems: [Item]?
        }
        let type: String?
        let data: Payload?
    }
}
