// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastIdentity.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/RedirectRefusal.swift
import Foundation
import Network
import Synchronization

enum AppPaths {
    static func applicationSupport() -> URL { URL.applicationSupportDirectory.appending(path: "unused") }
}

@main
struct NotchcastIdentityTest {
    nonisolated static let requests = Mutex<[String]>([])

    static func main() async throws {
        let debug = NotchcastIdentity(bundleIdentifier: "app.notchcast.dev")
        let release = NotchcastIdentity(bundleIdentifier: "app.notchcast")
        assert(debug.suiteName() == "app.notchcast.dev.notchcast")
        assert(release.suiteName() == "app.notchcast.notchcast")
        assert(debug.bundleID == "app.notchcast.dev")
        assert(release.bundleID == "app.notchcast")
        assert(debug.suiteName(suffix: ".editor") == "app.notchcast.dev.editor")
        assert(debug.suiteName(suffix: ".mach-link") == "app.notchcast.dev.mach-link")
        assert(debug.suiteName(suffix: ".urlCleaner") == "app.notchcast.dev.urlCleaner")
        assert(debug.suiteName(suffix: ".notchcast.agent-consent") == "app.notchcast.dev.notchcast.agent-consent")
        assert(release.suiteName(suffix: ".editor") == "app.notchcast.editor")
        assert(release.suiteName(suffix: ".mach-link") == "app.notchcast.mach-link")
        assert(release.suiteName(suffix: ".urlCleaner") == "app.notchcast.urlCleaner")
        assert(release.suiteName(suffix: ".notchcast.agent-consent") == "app.notchcast.notchcast.agent-consent")
        let missing = NotchcastIdentity(bundleIdentifier: nil)
        assert(missing.bundleID == "app.notchcast.dev")
        assert(missing.suiteName() == "app.notchcast.dev.notchcast")
        assert(NotchcastIdentity.releaseBundleIdentifier == "app.notchcast")
        let configuration = NotchcastIdentity.sessionConfiguration()
        assert(configuration.urlCache == nil)
        assert(configuration.urlCredentialStorage !== URLCredentialStorage.shared)
        assert(configuration.httpCookieStorage !== HTTPCookieStorage.shared)
        print("PASS identity preserves Debug/Release suites, bundle fallback and private sessions")

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                let line = String((String(bytes: data ?? Data(), encoding: .utf8) ?? "").prefix { !$0.isNewline })
                requests.withLock { $0.append(line) }
                let head = line.contains("/next") ? "200 OK" : "302 Found\r\nLocation: /next"
                let reply = "HTTP/1.1 \(head)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: .global())
        for _ in 0..<100 where (listener.port?.rawValue ?? 0) == 0 { try await Task.sleep(for: .milliseconds(20)) }
        guard let port = listener.port?.rawValue, port != 0 else { fatalError("Listener did not start") }
        defer { listener.cancel() }
        let session = URLSession(configuration: configuration, delegate: RedirectRefusal(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (_, response) = try await session.data(from: URL(string: "http://127.0.0.1:\(port)/start")!)
        precondition((response as? HTTPURLResponse)?.statusCode == 302, "The redirect answer is returned, not followed")
        let seen = requests.withLock { $0 }
        precondition(seen == ["GET /start HTTP/1.1"], "The redirect target is never requested: \(seen)")
        print("PASS a redirect is refused and its target is never requested")
    }
}
