import Foundation

enum DayHTTPService {
    private static let session: URLSession = {
        let configuration = NotchcastIdentity.sessionConfiguration()
        return URLSession(configuration: configuration)
    }()

    static func data(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Notchcast", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
