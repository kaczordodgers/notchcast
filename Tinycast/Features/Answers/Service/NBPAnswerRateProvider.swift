import Foundation

struct NBPAnswerRateProvider: Sendable {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, Int)

    private let fetch: Fetch

    init(fetch: @escaping Fetch = Self.fetch) {
        self.fetch = fetch
    }

    func rates(fetchedAt: Date) async throws -> NBPAnswerRates {
        var request = URLRequest(url: URL(string: "https://api.nbp.pl/api/exchangerates/tables/A?format=json")!)
        request.timeoutInterval = 10
        let (data, status) = try await fetch(request)
        try Task.checkCancellation()
        guard status == 200 else { throw URLError(.badServerResponse) }
        return try NBPAnswerRates.decode(data, fetchedAt: fetchedAt)
    }

    private static func fetch(_ request: URLRequest) async throws -> (Data, Int) {
        let configuration = NotchcastIdentity.sessionConfiguration()
        configuration.timeoutIntervalForResource = 10
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
