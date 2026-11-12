import Foundation

nonisolated enum AIUsageProvider {
    static func gatewayURL(_ gateway: String) throws -> URL {
        let address = gateway.trimmingCharacters(in: .whitespacesAndNewlines)
        let qualified = address.contains("://") ? address : "http://" + address
        guard let base = URL(string: qualified), ["http", "https"].contains(base.scheme),
              let host = base.host, !host.isEmpty, base.user == nil, base.password == nil,
              base.query == nil, base.fragment == nil else { throw URLError(.badURL) }
        return base
    }

    @concurrent
    static func fetch(gateway: String, now: Date) async throws -> [AIUsageSnapshot] {
        let base = try gatewayURL(gateway)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: base.appending(path: "v1/magpie/quotas"))
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        try Task.checkCancellation()
        return try MagpieQuotaDecoder.decode(data, now: now)
    }
}
