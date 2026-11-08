import Foundation

@MainActor final class TorrentRPCClient: NSObject, URLSessionTaskDelegate {
    private struct Response<Value: Decodable & Sendable>: Decodable, Sendable {
        struct Failure: Decodable, Sendable { let code: Int; let message: String }
        let jsonrpc: String
        let id: String
        let result: Value?
        let error: Failure?
    }

    private let secret: String
    private var session: URLSession?

    init(port: UInt16, secret: String) {
        self.secret = secret
        super.init()
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port)
        components.path = "/jsonrpc"
        rpcURL = components.url
        let configuration = NotchcastIdentity.sessionConfiguration()
        configuration.httpCookieStorage = nil
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 3
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    private var rpcURL: URL?

    func call<Value: Decodable & Sendable>(
        _ method: String, parameters: [Any] = [], as: Value.Type = Value.self
    ) async throws -> Value {
        guard let session, let rpcURL else { throw TorrentFailure.rpcUnavailable }
        let id = UUID().uuidString
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": id, "method": "aria2.\(method)",
            "params": ["token:\(secret)"] + parameters,
        ])
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            try Task.checkCancellation()
            throw TorrentFailure.rpcUnavailable
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse,
              http.url == rpcURL, data.count <= 16 * 1024 * 1024 else { throw TorrentFailure.invalidResponse }
        let envelope: Response<Value>
        do {
            envelope = try await Self.decode(data, as: Value.self)
        } catch {
            throw TorrentFailure.invalidResponse
        }
        guard envelope.id == id, envelope.jsonrpc == "2.0" else { throw TorrentFailure.invalidResponse }
        if let error = envelope.error { throw TorrentFailure.rpc(code: error.code, message: error.message) }
        guard http.statusCode == 200, let result = envelope.result else { throw TorrentFailure.invalidResponse }
        return result
    }

    @concurrent private static func decode<Value: Decodable & Sendable>(
        _ data: Data, as: Value.Type
    ) async throws -> Response<Value> {
        try JSONDecoder().decode(Response<Value>.self, from: data)
    }

    func invalidate() {
        session?.invalidateAndCancel()
        session = nil
    }

    nonisolated func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
