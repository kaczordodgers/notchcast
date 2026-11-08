import Foundation

final class AppUpdateTransport: NSObject, URLSessionTaskDelegate, Sendable {
    private let session: URLSession = {
        let config = NotchcastIdentity.sessionConfiguration()
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    func fetch(_ url: URL) async throws -> Data {
        guard url.scheme?.lowercased() == "https" else { throw URLError(.unsupportedURL) }
        let (bytes, response) = try await session.bytes(for: URLRequest(url: url), delegate: self)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.expectedContentLength <= AppUpdateFeed.limit else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < AppUpdateFeed.limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
