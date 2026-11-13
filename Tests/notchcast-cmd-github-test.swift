// notchcast-sources: Tinycast/Features/GitHub/Model/*.swift
// notchcast-sources: Tinycast/Features/GitHub/Service/*.swift
// notchcast-sources: Tinycast/Platform/KeychainSecretStore.swift
import Foundation
import Synchronization

@main
struct GitHubTest {
    static let fixture = #"{"full_name":"swiftlang/swift","description":"Language","stargazers_count":99}"#

    static func service(_ body: String, status: Int = 200,
                        headers: [String: String] = [:]) -> GitHubService {
        GitHubService(fetch: { request in
            (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status,
                                            httpVersion: nil, headerFields: headers)!)
        })
    }

    @MainActor
    static func main() async throws {
        let repos = try await service("{\"items\":[\(fixture)]}").search("swift & tools")
        precondition(repos.first?.fullName == "swiftlang/swift")
        precondition(repos.first?.url.absoluteString == "https://github.com/swiftlang/swift")
        let empty = try await service(#"{"items":[]}"#).search("none")
        precondition(empty.isEmpty)
        let html = #"<article class="Box-row"><h2 class="h3 lh-condensed"><a href="/swiftlang/swift">Swift</a></h2></article>"#
        let trending = try await service(html).search("  \n")
        precondition(trending.count == 1)
        for (api, expected) in [
            (service("{}", status: 429), GitHubService.Failure.rateLimited),
            (service("{}", status: 403, headers: ["X-RateLimit-Remaining": "0"]), .rateLimited),
            (service("{}", status: 500), .http(500)),
            (service("{}", status: 403), .http(403)),
            (service("garbled"), .malformedResponse),
            (service(#"{"items":[{"full_name":"../bad","stargazers_count":0}]}"#), .malformedResponse)
        ] {
            do {
                _ = try await api.search("x")
                preconditionFailure("Expected error")
            } catch let error as GitHubService.Failure { precondition(error == expected) }
        }
        let noToken = GitHubService(fetch: { _ in preconditionFailure("No token must not fetch") })
        do {
            _ = try await noToken.starred()
            preconditionFailure("Expected token requirement")
        } catch let error as GitHubService.Failure { precondition(error == .tokenRequired) }
        let stars = GitHubService(fetch: { request in
            precondition(request.url?.path == "/user/starred")
            return (Data("[\(fixture)]".utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                                                            httpVersion: nil, headerFields: nil)!)
        }, token: { UUID().uuidString })
        let starred = try await stars.starred()
        precondition(starred.first?.isStarred == true)
        precondition(GitHubHTMLEntities.decode("&amp;&lt;&gt;&quot;&apos;&nbsp;&#39;&#x1F680;&#X41;&copy;&amp;lt; café")
                     == "&<>\"'\u{00a0}'🚀A&copy;&lt; café")
        let calls = Mutex(0)
        let capped = GitHubService(fetch: { request in
            calls.withLock { $0 += 1 }
            let body = "[" + Array(repeating: fixture, count: 100).joined(separator: ",") + "]"
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                                                    httpVersion: nil, headerFields: nil)!)
        }, token: { "fixture" })
        let cached = GitHubSearchSession(service: capped, sleep: { _ in })
        for query in ["swift", "language", "missing"] {
            cached.search(query, scope: .starred)
            for _ in 0..<500 where cached.state == .loading { try await Task.sleep(for: .milliseconds(10)) }
            precondition(cached.state == .ready)
        }
        precondition(calls.withLock { $0 } == 10)
        cached.cancel()
        cached.search("swift", scope: .starred)
        for _ in 0..<500 where cached.state == .loading { try await Task.sleep(for: .milliseconds(10)) }
        precondition(calls.withLock { $0 } == 20)
        print("Verified: starred session cache, refresh invalidation, ten-page cap and HTML5 entities")
        let debounced = GitHubService(fetch: { request in
            let parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            precondition(parts.queryItems?.first(where: { $0.name == "q" })?.value == "new")
            return (Data("{\"items\":[\(fixture)]}".utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let session = GitHubSearchSession(service: debounced)
        session.search("old")
        try await Task.sleep(for: .milliseconds(400))
        session.search("new")
        try await Task.sleep(for: .milliseconds(400))
        precondition(session.state == .loading && session.results.isEmpty)
        for _ in 0..<500 where session.state == .loading {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(session.state == .ready && session.results.count == 1)
        session.search("cancel")
        session.cancel()
        try await Task.sleep(for: .milliseconds(750))
        precondition(session.state == .idle && session.results.isEmpty)
        let starsSession = GitHubSearchSession(service: stars, sleep: { _ in })
        starsSession.search("language", scope: .starred)
        for _ in 0..<100 where starsSession.state == .loading {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(starsSession.results.first?.isStarred == true)
        starsSession.search("missing", scope: .starred)
        for _ in 0..<100 where starsSession.state == .loading {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(starsSession.state == .ready && starsSession.results.isEmpty)
        print("Verified: search, empty query Trending, HTTP/rate limit, malformed JSON, stars without token")
        print("Verified: 700 ms trailing debounce and cancellation; fake network only")
    }
}
