// notchcast-sources: Tinycast/Features/AgentFleet/BotHost/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentFleet/BotHost/Service/*.swift
// notchcast-sources: Tinycast/Features/AgentFleet/BotHost/BotHostModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
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
        var captured = request
        if captured.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            captured.httpBody = data
        }
        let fixture = Self.state.withLock { state in
            state.requests.append(captured)
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
            return .init(url: URL(string: "http://127.0.0.1:\(54321 + count)")!, token: "fixture-\(count)")
        }, protocolClasses: [FixtureProtocol.self])
        for _ in 0..<2 {
            let reply = try await transport.call(path: ["api", "hello"], body: Data("{}".utf8), as: Reply.self)
            precondition(reply.value == 1)
        }
        let requests = FixtureProtocol.state.withLock { $0.requests }
        precondition(requests.count == 2 && calls.withLock { $0 } == 2)
        for (index, request) in requests.enumerated() {
            precondition(request.url?.path == "/api/hello")
            precondition(request.url?.port == 54322 + index)
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
        for status in [302, 401, 500] {
            FixtureProtocol.state.withLock {
                $0 = .init(response: Data("{\"error\":\"fixture-secret\"}".utf8), status: status)
            }
            do {
                _ = try await transport.call(path: ["api"], body: Data(), as: Reply.self)
                fatalError("Accepted HTTP failure")
            } catch {
                precondition(error is BotHostTransport.Failure)
                precondition(!String(describing: error).contains("fixture-secret"))
            }
            precondition(FixtureProtocol.state.withLock { $0.requests.count } == 1)
        }
        let unavailable = BotHostTransport(connection: {
            throw NSError(domain: "fixture-secret", code: 1)
        }, protocolClasses: [FixtureProtocol.self])
        do {
            _ = try await unavailable.call(path: ["api"], body: Data(), as: Reply.self)
            fatalError("Accepted missing credentials")
        } catch {
            precondition(!String(describing: error).contains("fixture-secret"))
        }
        try await adapters()
        print("Bot host transport fixtures passed")
    }

    static func fixture(_ json: String) {
        FixtureProtocol.state.withLock {
            $0 = .init(response: Data(json.utf8))
        }
    }

    static func request(_ path: String, keys: Set<String>) throws {
        let requests = FixtureProtocol.state.withLock { $0.requests }
        guard let request = requests.last else { fatalError("No fixture request") }
        precondition(request.url?.path == path)
        precondition(request.httpMethod == "POST")
        precondition(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer fixture-") == true)
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        precondition(Set(body?.keys.map { $0 } ?? []) == keys)
        if keys.contains("botId") { precondition(body?["botId"] as? String == "synthetic") }
        if keys.contains("text") {
            precondition(["Hello", "Answer"].contains(body?["text"] as? String ?? ""))
        }
        if keys.contains("requestId") { precondition(body?["requestId"] as? String == "question") }
        if keys.contains("entryId") { precondition(body?["entryId"] as? String == "q") }
        if keys.contains("optionId") { precondition(body?["optionId"] as? String == "yes") }
        if keys.contains("since") { precondition(body?["since"] as? Int == 0) }
        if keys.contains("clientNonce") {
            precondition(UUID(uuidString: body?["clientNonce"] as? String ?? "") != nil)
        }
    }

    @MainActor
    static func adapters() async throws {
        let calls = Mutex(0)
        let transport = BotHostTransport(connection: {
            let count = calls.withLock { $0 += 1; return $0 }
            return .init(url: URL(string: "http://[::1]:54321")!, token: "fixture-\(count)")
        }, protocolClasses: [FixtureProtocol.self])
        let bridge = OpenBotBridge(transport: transport)
        fixture("""
        {"exitCode":0,"bots":[{"id":"synthetic","name":"Fixture"},
        {"id":"","name":"Excluded fixture"}],"future":1}
        """)
        let bots = try await bridge.list()
        precondition(bots == [.init(id: "synthetic", name: "Fixture")])
        try request("/api/list", keys: [])
        fixture("{\"exitCode\":0}")
        _ = try await bridge.message(botID: "synthetic", text: "Hello")
        try request("/api/message", keys: ["botId", "text"])
        _ = try await bridge.status(botID: "synthetic")
        try request("/api/status", keys: ["botId"])
        _ = try await bridge.answer(botID: "synthetic", requestID: "question", text: "Answer")
        try request("/api/answer", keys: ["botId", "requestId", "text"])
        _ = try await bridge.approve(botID: "synthetic", requestID: "question", optionID: "yes")
        try request("/api/approve", keys: ["botId", "requestId", "optionId"])
        fixture("{\"exitCode\":3,\"pending\":[{\"id\":\"q\",\"text\":\"Question\",\"options\":[\"yes\"]}]}")
        let pending = try await bridge.pending(botID: "synthetic")
        precondition(pending == [.init(id: "q", text: "Question", options: ["yes"])])
        try request("/api/pending", keys: ["botId"])
        for code in [0, 1, 3, 4, 5, 99] {
            fixture("{\"exitCode\":\(code)}")
            let state = try await bridge.status(botID: "synthetic")
            precondition(state == BotHostState(exitCode: code))
        }
        for operation in 0..<6 {
            do {
                switch operation {
                case 0: _ = try await bridge.message(botID: "", text: "Fixture")
                case 1: _ = try await bridge.status(botID: "")
                case 2: _ = try await bridge.pending(botID: "")
                case 3: _ = try await bridge.answer(botID: "", requestID: "q", text: "Fixture")
                default: _ = try await bridge.approve(botID: "", requestID: "q", optionID: "yes")
                }
                fatalError("Excluded fixture was sent")
            } catch BotHostTransport.Failure.rejected {}
        }
        precondition(FixtureProtocol.state.withLock { $0.requests.count } == 1)
        let host = CodyncHostClient(transport: transport)
        let snapshot = """
        {"bots":[{"id":"synthetic","name":"Fixture","status":"needsInput"},
        {"id":"","name":"Excluded fixture","status":"idle"}],
        "entries":[{"id":"q","botId":"synthetic","kind":"permission",
        "data":{"text":"Question","status":"pending","options":[{"optionId":"yes"}]}}],"future":1}
        """
        fixture(snapshot)
        let hostBots = try await host.list()
        precondition(hostBots == bots)
        try request("/api/sync", keys: ["since"])
        let state = try await host.status(botID: "synthetic")
        precondition(state == .waitingForPerson)
        let permissions = try await host.pending(botID: "synthetic")
        precondition(permissions == pending)
        fixture("{\"entry\":{\"id\":\"sent\",\"botId\":\"synthetic\",\"kind\":\"user\",\"data\":{}}}")
        _ = try await host.message(botID: "synthetic", text: "Hello")
        try request("/api/send", keys: ["botId", "text", "clientNonce"])
        _ = try await host.answer(botID: "synthetic", requestID: "q", text: "Answer")
        try request("/api/send", keys: ["botId", "text", "clientNonce"])
        fixture(snapshot)
        _ = try await host.approve(botID: "synthetic", requestID: "q", optionID: "yes")
        try request("/api/respondPermission", keys: ["entryId", "optionId"])
        do {
            _ = try await host.status(botID: "")
            fatalError("Excluded fixture was queried")
        } catch BotHostTransport.Failure.rejected {}
        for (status, expected): (String, BotHostState) in [
            ("idle", .done), ("working", .working), ("needsInput", .waitingForPerson), ("error", .failed)
        ] {
            fixture("{\"bots\":[{\"id\":\"synthetic\",\"name\":\"Fixture\",\"status\":\"\(status)\"}],\"entries\":[]}")
            let actual = try await host.status(botID: "synthetic")
            precondition(actual == expected)
        }
        fixture("{}")
        do { _ = try await host.list(); fatalError("Accepted missing fields") } catch
        BotHostTransport.Failure.invalidResponse {}
        do { _ = try await bridge.list(); fatalError("Accepted missing fields") } catch
        BotHostTransport.Failure.invalidResponse {}
        FixtureProtocol.state.withLock { $0.error = URLError(.cannotConnectToHost) }
        let unreachable = try await host.status(botID: "synthetic")
        precondition(unreachable == .unreachable)
        let module = BotHostModule(client: bridge)
        do { _ = try await module.list(); fatalError("Disabled module called host") } catch
        BotHostTransport.Failure.rejected {}
        module.start()
        fixture("{\"exitCode\":0,\"bots\":[]}")
        _ = try await module.list()
        module.stop()
        do { _ = try await module.list(); fatalError("Stopped module called host") } catch
        BotHostTransport.Failure.rejected {}
        precondition(!NotchcastFeature.botHost.isSystemFeature && !NotchcastFeature.botHost.needsIsland)
        precondition(NotchcastFeature.botHost.settingsGroup == .activities)
        for (json, expected): (String, CodyncHostEvent?) in [
            ("{\"type\":\"hello\",\"hostId\":\"fixture\",\"rev\":7}", .hello(hostID: "fixture", revision: 7)),
            ("{\"type\":\"bot\",\"bot\":{\"id\":\"b\",\"status\":\"idle\"}}", .bot(id: "b", status: "idle")),
            ("{\"type\":\"bot\",\"bot\":{\"id\":\"b\",\"deleted\":true,\"rev\":8}}", .botDeleted(id: "b", revision: 8)),
            ("{\"type\":\"entry\",\"entry\":{\"id\":\"e\",\"botId\":\"b\"}}", .entry(id: "e", botID: "b")),
            ("{\"type\":\"resync\"}", .resync), ("{\"type\":\"future\"}", .unknown), ("broken", nil),
            ("{\"type\":\"bot\",\"bot\":{\"id\":\"\",\"status\":\"idle\"}}", nil)
        ] {
            precondition(CodyncHostEvent.parse(Data(json.utf8)) == expected)
        }
        let sent = FixtureProtocol.state.withLock { $0.requests }
        precondition(calls.withLock { $0 } >= sent.count)
    }
}
