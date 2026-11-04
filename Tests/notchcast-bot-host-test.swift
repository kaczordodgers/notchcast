// notchcast-sources: Tinycast/Features/AgentFleet/BotHost/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentFleet/BotHost/Service/*.swift
import Foundation
import Synchronization

private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    struct State {
        var requests: [URLRequest] = []
        var response = Data("{\"value\":1,\"future\":true}".utf8)
        var status = 200
        var error: URLError?
    }
    static let state = Mutex(State())
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let fixture = Self.state.withLock { state in
            state.requests.append(request)
            return state
        }
        if let error = fixture.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: fixture.status,
                                             httpVersion: nil, headerFields: nil)
        else { fatalError("Invalid fixture") }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: fixture.response)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
private enum BotHostTest {
    struct Reply: Decodable, Sendable { let value: Int }

    static func main() async throws {
        for (code, expected): (Int, BotHostState) in [
            (0, .done), (1, .failed), (3, .waitingForPerson),
            (4, .timedOut), (5, .unreachable), (99, .failed)
        ] {
            precondition(BotHostState(exitCode: code) == expected)
        }
        let calls = Mutex(0)
        let transport = BotHostTransport(connection: {
            let count = calls.withLock { $0 += 1; return $0 }
            return .init(url: URL(string: "http://127.0.0.1:54321")!, token: "fixture-\(count)")
        }, protocolClasses: [FixtureProtocol.self])
        for _ in 0..<2 {
            let reply = try await transport.call(path: ["api", "hello"], body: Data("{}".utf8), as: Reply.self)
            precondition(reply.value == 1)
        }
        let requests = FixtureProtocol.state.withLock { $0.requests }
        precondition(requests.count == 2 && calls.withLock { $0 } == 2)
        for (index, request) in requests.enumerated() {
            precondition(request.url?.path == "/api/hello")
            precondition(request.httpMethod == "POST")
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-\(index + 1)")
            precondition(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        }
        for url in ["http://example.com", "http://127.0.0.1.example.com", "http://localhost",
                    "http://192.168.1.1", "http://user:pass@127.0.0.1", "file:///tmp/fixture"] {
            let refused = BotHostTransport(connection: {
                .init(url: URL(string: url)!, token: "fixture-secret")
            }, protocolClasses: [FixtureProtocol.self])
            do {
                _ = try await refused.call(path: ["api"], body: Data(), as: Reply.self)
                fatalError("Accepted remote host")
            } catch BotHostTransport.Failure.invalidConnection {}
        }
        precondition(FixtureProtocol.state.withLock { $0.requests.count } == 2)
        FixtureProtocol.state.withLock { $0.response = Data("fixture-secret".utf8) }
        do {
            _ = try await transport.call(path: ["api"], body: Data(), as: Reply.self)
            fatalError("Accepted malformed response")
        } catch {
            precondition(error is BotHostTransport.Failure)
            precondition(!String(describing: error).contains("fixture-secret"))
        }
        FixtureProtocol.state.withLock { $0.error = URLError(.timedOut) }
        do {
            _ = try await transport.call(path: ["api"], body: Data(), as: Reply.self)
            fatalError("Accepted timeout")
        } catch BotHostTransport.Failure.timedOut {}
        print("Bot host transport fixtures passed")
    }
}
