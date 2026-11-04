import Foundation

final class BotHostTransport: Sendable {
    struct Connection: Sendable {
        let url: URL
        let token: String
    }

    enum Failure: LocalizedError, Sendable {
        case invalidConnection, unreachable, timedOut, invalidResponse, rejected

        var errorDescription: String? {
            switch self {
            case .invalidConnection: String(localized: "Set a loopback URL and token for the bot host.")
            case .unreachable: String(localized: "Cannot reach the bot host.")
            case .timedOut: String(localized: "The bot host request timed out.")
            case .invalidResponse: String(localized: "The bot host returned an invalid response.")
            case .rejected: String(localized: "The bot host rejected the request.")
            }
        }
    }

    private final class RedirectPolicy: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    private let connection: @Sendable () throws -> Connection
    private let session: URLSession

    init(
        connection: @escaping @Sendable () throws -> Connection,
        protocolClasses: [AnyClass]? = nil
    ) {
        self.connection = connection
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.connectionProxyDictionary = [:]
        configuration.protocolClasses = protocolClasses
        session = URLSession(configuration: configuration, delegate: RedirectPolicy(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    func call<Response: Decodable & Sendable>(
        path: [String], body: Data, as type: Response.Type
    ) async throws -> Response {
        try Task.checkCancellation()
        let current: Connection
        do { current = try connection() } catch { throw Failure.invalidConnection }
        guard Self.isLoopback(current.url), !current.token.isEmpty,
              !current.token.contains(where: { $0.isNewline || $0 == "\r" })
        else { throw Failure.invalidConnection }
        var url = current.url
        for component in path {
            guard !component.isEmpty, component != ".", component != "..",
                  !component.contains("/"), !component.contains("%")
            else { throw Failure.invalidConnection }
            url.appendPathComponent(component)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer " + current.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            try Task.checkCancellation()
            if (error as? URLError)?.code == .timedOut { throw Failure.timedOut }
            throw Failure.unreachable
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw Failure.rejected }
        do { return try JSONDecoder().decode(type, from: data) } catch { throw Failure.invalidResponse }
    }

    private static func isLoopback(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "http" || parts.scheme == "https",
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              let host = parts.host
        else { return false }
        if host == "[::1]" || host == "::1" { return true }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == 4 && octets.first == "127" && octets.allSatisfy {
            guard let number = UInt8($0) else { return false }
            return String(number) == $0
        }
    }
}
