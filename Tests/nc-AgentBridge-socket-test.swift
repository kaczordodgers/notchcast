import Darwin
import Foundation
import Synchronization

@main
@MainActor
struct AgentSocketTests {
    final class ClientFixture: @unchecked Sendable {
        let session = AgentSocketClient.Session()
    }
    @MainActor
    final class CancellationFixture {
        var started = 0
        var cancelled = 0

        func run() async -> AgentReply {
            started += 1
            do { try await Task.sleep(for: .seconds(10)) } catch {
                cancelled += 1
                return .init(code: .failed)
            }
            return .init(code: .ok)
        }
    }

    nonisolated static func check(_ value: Bool, _ message: String = "check failed") { precondition(value, message) }

    // Blocking calls stay off the cooperative pool; a small runner would starve the handler.
    static func offPool<Value: Sendable>(_ work: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: work()) }
        }
    }

    static func send(_ request: AgentRequest, _ url: URL) async -> AgentReply {
        await offPool { AgentSocketClient.send(request, to: url) }
    }

    static func main() async throws {
        let folder = URL(filePath: "/tmp/nc-agent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "private/socket")
        let index = AgentActionIndex()
        try index.register(.init(action: .init(id: "fixture.echo", title: "Echo", danger: .harmless),
                                 run: { _ in .string("dispatched") }))
        index.start()
        let server = AgentSocketServer(socketURL: url, readTimeout: .milliseconds(100), handlerTimeout: 0.2) {
            await index.handle($0)
        }
        try server.start()
        defer { server.stop() }
        var info = stat()
        check(lstat(url.path, &info) == 0 && info.st_mode & 0o777 == 0o600)
        check(lstat(url.deletingLastPathComponent().path, &info) == 0 && info.st_mode & 0o777 == 0o700)
        check(await send(.init(verb: .run, id: "fixture.echo"), url) == .init(code: .ok, result: .string("dispatched")))
        let competitor = AgentSocketServer(socketURL: url) { _ in .init(code: .failed) }
        do { try competitor.start(); preconditionFailure("active listener replaced") } catch {}
        check((await send(.init(verb: .status), url)).code == .ok)

        let replies = await withTaskGroup(of: AgentReply.self, returning: [AgentReply].self) { group in
            for _ in 0..<4 {
                group.addTask { await send(.init(verb: .status), url) }
            }
            var values: [AgentReply] = []
            for await reply in group { values.append(reply) }
            return values
        }
        check(replies.count == 4 && replies.allSatisfy { $0.code == .ok })
        let malformed = await offPool { () -> AgentReply in
            let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
            defer { Darwin.close(descriptor) }
            do {
                var address = try AgentSocketIO.address(url.path)
                try AgentSocketIO.configure(descriptor)
                let result = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }
                guard result == 0 else { return .init(code: .notRunning) }
                try AgentSocketIO.write(Data("not-json\n".utf8), to: descriptor, timeout: .seconds(1))
                return try JSONDecoder().decode(AgentReply.self,
                                               from: AgentSocketIO.readLine(descriptor, timeout: .seconds(1)))
            } catch { return .init(code: .failed) }
        }
        check(malformed.code == .badRequest)
        server.stop()
        check(!FileManager.default.fileExists(atPath: url.path))
        check(await send(.init(verb: .status), url) == .init(code: .notRunning))
        try server.start()
        check((await send(.init(verb: .status), url)).code == .ok)
        server.stop()

        let initializations = Mutex(0)
        let persistent = AgentSocketServer(socketURL: url, handlerTimeout: 0.05) { request in
            if case .string = request.parameters { initializations.withLock { $0 += 1 } }
            if request.id == "slow" {
                try? await Task.sleep(for: .seconds(1))
            }
            return .init(code: .ok)
        }
        try persistent.start()
        await offPool {
            let clients = (0..<64).map { _ in AgentSocketClient.Session() }
            for client in clients {
                check(client.send(.init(verb: .mcp, id: "fast"), to: url).code == .ok)
            }
            check(AgentSocketClient.send(.init(verb: .status), to: url).code == .ok)
            check(AgentSocketClient.Session().send(.init(verb: .mcp, id: "overflow"), to: url).code == .failed)
            withExtendedLifetime(clients) {}
        }
        print("PASS 64 MCP connections leave plain CLI available; connection 65 is refused")
        let client = ClientFixture()
        check(await offPool {
            client.session.send(.init(verb: .mcp, id: "fast",
                parameters: .string(#"{"method":"initialize"}"#)), to: url).code
        } == .ok)
        check(await offPool { client.session.send(.init(verb: .mcp, id: "slow"), to: url).code } == .failed)
        check(await offPool { client.session.send(.init(verb: .mcp, id: "fast"), to: url).code } == .ok)
        check(initializations.withLock { $0 } == 2)
        persistent.stop()
        try persistent.start()
        _ = await offPool { client.session.send(.init(verb: .mcp, id: "fast"), to: url) }
        check(await offPool { client.session.send(.init(verb: .mcp, id: "fast"), to: url).code } == .ok)
        check(initializations.withLock { $0 } == 3)
        persistent.stop()
        print("PASS same client recovers after handler timeout and server restart")

        let stalled = AgentSocketServer(socketURL: url, handlerTimeout: 0.05) { _ in
            do { try await Task.sleep(for: .seconds(10)) } catch { return .init(code: .failed) }
            return .init(code: .ok)
        }
        try stalled.start()
        check(await send(.init(verb: .status), url) == .init(code: .failed))
        stalled.stop()

        let cancellation = CancellationFixture()
        let cancellable = AgentSocketServer(socketURL: url) { _ in await cancellation.run() }
        try cancellable.start()
        let pending = Task { await send(.init(verb: .status), url) }
        while cancellation.started == 0 { await Task.yield() }
        cancellable.stop()
        check((await pending.value).code == .failed)
        while cancellation.cancelled == 0 { await Task.yield() }
        check(cancellation.cancelled == 1, "stop left the handler running")

        try cancellable.start()
        let disconnected = await offPool { () -> Int32 in
            let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
            do {
                var address = try AgentSocketIO.address(url.path)
                try AgentSocketIO.configure(descriptor)
                let result = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }
                precondition(result == 0)
                try AgentSocketIO.write(AgentSocketIO.frame(AgentRequest(verb: .status)),
                                        to: descriptor, timeout: .seconds(1))
                return descriptor
            } catch {
                Darwin.close(descriptor)
                preconditionFailure("fixture client failed: \(error)")
            }
        }
        while cancellation.started < 2 { await Task.yield() }
        check(cancellation.started == 2)
        Darwin.close(disconnected)
        while cancellation.cancelled < 2 { await Task.yield() }
        check(cancellation.cancelled == 2, "disconnect left the handler running")
        cancellable.stop()

        let protected = folder.appending(path: "protected")
        try Data("keep".utf8).write(to: protected)
        let unsafe = AgentSocketServer(socketURL: protected) { _ in .init(code: .ok) }
        do { try unsafe.start(); preconditionFailure("ordinary file replaced") } catch {}
        check(try String(contentsOf: protected, encoding: .utf8) == "keep")
        let link = folder.appending(path: "linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url.deletingLastPathComponent())
        let linked = AgentSocketServer(socketURL: link.appending(path: "socket")) { _ in .init(code: .ok) }
        do { try linked.start(); preconditionFailure("symlink directory accepted") } catch {}
        do { _ = try AgentSocketIO.address(String(repeating: "x", count: AgentSocketIO.pathLimit + 1))
            preconditionFailure("long socket path accepted")
        } catch {}
        check(!AgentSocketIO.isSameUser(-1))
        try server.start()
        try FileManager.default.removeItem(at: url)
        try Data("replacement".utf8).write(to: url)
        server.stop()
        check(try String(contentsOf: url, encoding: .utf8) == "replacement", "cleanup deleted a replacement file")
        print("PASS: private socket, same-user peers, concurrency, locking, framing, timeouts, restart and safe paths")
    }
}
