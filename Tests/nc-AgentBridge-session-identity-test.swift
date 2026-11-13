import Foundation

@main
@MainActor
struct AgentSessionIdentityTests {
    static func main() async throws {
        let folder = URL(filePath: "/tmp/nc-session-\(UUID().uuidString)")
        let url = folder.appending(path: "socket")
        let server = AgentSocketServer(socketURL: url) { request in
            .init(code: .ok, result: .string(request.id ?? ""))
        }
        try server.start()
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: folder)
        }
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let old = AgentSocketClient.Session()
                let replacement = AgentSocketClient.Session()
                let request = AgentRequest(verb: .mcp, id: "same-client")
                let first = old.send(request, to: url)
                let second = replacement.send(request, to: url)
                precondition(first.code == .ok && second.code == .ok && first.result != second.result,
                             "reconnect reused stale session identity")
                precondition(replacement.send(request, to: url) == second)
                continuation.resume()
            }
        }
        print("PASS reconnect isolates session identity from stale cleanup")
    }
}
