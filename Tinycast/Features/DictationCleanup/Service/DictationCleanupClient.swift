import Foundation

protocol DictationCleanupClient: Sendable {
    /// Prompt cancellation lets the timeout join its child request without delaying insertion.
    func clean(_ request: URLRequest) async throws -> String
}

struct DictationCleanupHTTPClient: DictationCleanupClient {
    enum Failure: Error { case invalidEndpoint, invalidResponse }

    private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    private struct Reply: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
        let stop_reason: String
    }

    func clean(_ request: URLRequest) async throws -> String {
        let configuration = NotchcastIdentity.sessionConfiguration()
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForResource = request.timeoutInterval
        let session = URLSession(configuration: configuration, delegate: RedirectBlocker(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        return try Self.text(from: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    static func request(
        raw: String, language: String?, settings: DictationCleanupSettings, key: String,
        systemPrompt: String? = nil
    ) throws -> URLRequest {
        guard let base = URL(string: settings.baseURL),
              ["http", "https"].contains(base.scheme),
              let host = base.host(), ["localhost", "127.0.0.1", "::1"].contains(host),
              base.user == nil, base.password == nil, base.query == nil, base.fragment == nil,
              ["", "/", "/v1", "/v1/"].contains(base.path)
        else { throw Failure.invalidEndpoint }
        let endpoint = base.path.hasPrefix("/v1")
            ? base.appendingPathComponent("messages") : base.appendingPathComponent("v1/messages")
        var request = URLRequest(url: endpoint, timeoutInterval: 4)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "claude-sonnet-5-5", "max_tokens": 4_096,
            "system": systemPrompt ?? DictationCleanupPrompt.system(settings: settings, language: language),
            "output_config": ["effort": settings.effort.rawValue],
            "messages": [["role": "user", "content": raw]]
        ])
        return request
    }

    static func text(from data: Data, status: Int) throws -> String {
        guard status == 200 else { throw Failure.invalidResponse }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        guard reply.stop_reason == "end_turn", !reply.content.isEmpty,
              reply.content.allSatisfy({ $0.type == "text" && $0.text != nil })
        else { throw Failure.invalidResponse }
        return reply.content.compactMap(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
