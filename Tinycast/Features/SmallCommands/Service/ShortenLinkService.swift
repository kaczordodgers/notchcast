import Foundation
import Darwin

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
        guard let link = NotchcastLink.clean(address),
            !link.contains(where: \.isWhitespace),
            let host = URL(string: link)?.host(), !Self.isPrivate(host) else { throw Failure.noLink }
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
            if let url = match.url, let clean = NotchcastLink.clean(url.absoluteString) { return clean }
        }
        return nil
    }

    private static func isPrivate(_ raw: String) -> Bool {
        let host = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]."))
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") { return true }
        var ipv4 = in_addr()
        if inet_aton(host, &ipv4) == 1 {
            let value = UInt32(bigEndian: ipv4.s_addr)
            let first = value >> 24
            let second = (value >> 16) & 255
            return first == 0 || first == 10 || first == 127
                || (first == 169 && second == 254) || (first == 172 && (16...31).contains(second))
                || (first == 192 && second == 168)
        }
        var ipv6 = in6_addr()
        if inet_pton(AF_INET6, host, &ipv6) == 1 {
            let bytes = withUnsafeBytes(of: ipv6) { Array($0) }
            if bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 255, bytes[11] == 255 {
                return isPrivate(bytes.suffix(4).map(String.init).joined(separator: "."))
            }
            return bytes.prefix(15).allSatisfy { $0 == 0 } && bytes[15] <= 1
                || bytes[0] & 254 == 252 || (bytes[0] == 254 && bytes[1] & 192 == 128)
        }
        return false
    }

    private static func fetch(_ request: URLRequest) async throws -> (Data, Int) {
        let configuration = NotchcastIdentity.sessionConfiguration()
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
