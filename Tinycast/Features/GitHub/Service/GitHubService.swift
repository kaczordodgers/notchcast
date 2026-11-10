import Foundation

struct GitHubService: Sendable {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    typealias Token = @Sendable () throws -> String?

    enum Failure: Error, Equatable {
        case tokenRequired
        case rateLimited
        case http(Int)
        case malformedResponse
    }

    private struct SearchResponse: Decodable {
        let items: [GitHubRepository]
    }

    private let fetch: Fetch
    private let token: Token

    init(fetch: @escaping Fetch = GitHubService.network, token: @escaping Token = { nil }) {
        self.fetch = fetch
        self.token = token
    }

    init(account: UUID, fetch: @escaping Fetch = GitHubService.network) {
        self.init(fetch: fetch, token: {
            try KeychainSecretStore(scope: "github").secret(for: account)
        })
    }

    func search(_ query: String) async throws -> [GitHubRepository] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return try await trending() }
        let body = try await request(path: "/search/repositories", items: [
            URLQueryItem(name: "q", value: query), URLQueryItem(name: "per_page", value: "50")
        ])
        do {
            return try JSONDecoder().decode(SearchResponse.self, from: body).items
        } catch { throw Failure.malformedResponse }
    }

    func starred() async throws -> [GitHubRepository] {
        var repos: [GitHubRepository] = []
        var page = 1
        while page <= 10 {
            try Task.checkCancellation()
            let body = try await request(path: "/user/starred", items: [
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "page", value: String(page))
            ], requiresToken: true)
            let batch: [GitHubRepository]
            do {
                batch = try JSONDecoder().decode([GitHubRepository].self, from: body)
            } catch { throw Failure.malformedResponse }
            repos += batch.map { repo in
                var repo = repo
                repo.isStarred = true
                return repo
            }
            if batch.count < 100 { return repos }
            page += 1
        }
        return repos
    }

    func trending() async throws -> [GitHubRepository] {
        let body = try await request(path: "/trending", host: "github.com")
        guard let html = String(bytes: body, encoding: .utf8) else { throw Failure.malformedResponse }
        let articles = html.components(separatedBy: "<article class=\"Box-row\">").dropFirst()
        let repos = try articles.compactMap { article -> GitHubRepository? in
            guard let match = article.firstMatch(of:
                /<h2[^>]*>.*?href="\/([^"\/]+\/[^"\/]+)"/.dotMatchesNewlines())
            else { return nil }
            let description = article.firstMatch(of:
                /<p class="col-9[^"]*">\s*(.*?)\s*<\/p>/.dotMatchesNewlines())
                .map { GitHubHTMLEntities.decode(String($0.output.1)) }
            let stars = article.firstMatch(of:
                /href="\/[^\"]+\/stargazers"[^>]*>.*?<\/svg>\s*([\d,]+)\s*<\/a>/.dotMatchesNewlines())
                .flatMap { Int($0.output.1.replacingOccurrences(of: ",", with: "")) } ?? 0
            return try GitHubRepository(fullName: String(match.output.1), description: description, stars: stars)
        }
        guard !repos.isEmpty else { throw Failure.malformedResponse }
        return repos
    }

    private func request(path: String, host: String = "api.github.com",
                         items: [URLQueryItem] = [], requiresToken: Bool = false) async throws -> Data {
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = host
        parts.path = path
        parts.queryItems = items.isEmpty ? nil : items
        var request = URLRequest(url: parts.url!, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Notchcast", forHTTPHeaderField: "User-Agent")
        if host == "api.github.com" {
            let secret = try token()?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let secret, !secret.isEmpty {
                request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
            } else if requiresToken { throw Failure.tokenRequired }
        }
        let (data, response) = try await fetch(request)
        try Task.checkCancellation()
        if response.statusCode == 429 || (response.statusCode == 403
            && (response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0"
                || response.value(forHTTPHeaderField: "Retry-After") != nil)) {
            throw Failure.rateLimited
        }
        guard response.statusCode == 200 else { throw Failure.http(response.statusCode) }
        return data
    }

    private static let session: URLSession = {
        let configuration = NotchcastIdentity.sessionConfiguration()
        return URLSession(configuration: configuration)
    }()

    static func network(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw Failure.malformedResponse }
        return (data, response)
    }
}
