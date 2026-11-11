import Foundation

final class AppUpdateTransport: Sendable {
    private let session: URLSession = {
        let config = NotchcastIdentity.sessionConfiguration()
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config, delegate: RedirectRefusal(), delegateQueue: nil)
    }()

    func fetch(_ url: URL) async throws -> Data {
        guard url.scheme?.lowercased() == "https" else { throw URLError(.unsupportedURL) }
        let (bytes, response) = try await session.bytes(for: URLRequest(url: url))
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
}
