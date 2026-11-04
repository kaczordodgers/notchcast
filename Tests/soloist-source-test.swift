// notchcast-sources: Tinycast/Features/Music/Model/NowPlaying.swift
// notchcast-sources: Tinycast/Features/Music/Model/SoloistProtocol.swift
// notchcast-sources: Tinycast/Features/Music/Service/SoloistSource.swift
import Foundation
import Network

private let snapshot = #"""
{"type":"playback_state","status":"playing","is_active":true,
"item":{"decorations":{"identity":{"name":"Teardrop"},
"creators":[{"entity":{"decorations":{"identity":{"name":"Massive Attack"}}}}],
"parent":{"entity":{"decorations":{"identity":{"name":"Mezzanine"}}}},
"playback":{"duration_ms":331000}}},"position":{"position_ms":134000,"timestamp_ms":1000}}
"""#

@MainActor
private final class Server {
    let listener: NWListener
    var connections: [NWConnection] = []
    var commands: [String] = []
    var loggedIn = false
    var port: Int { Int(listener.port!.rawValue) }

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        listener.start(queue: .main)
    }

    func accept(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: .main)
        receive(connection)
    }

    func receive(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            Task { @MainActor in
                guard let self, error == nil, let data else { return }
                guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let command = object["command"] as? String else { fatalError("Invalid command") }
                self.commands.append(command)
                if command == "get_state" {
                    self.send(self.loggedIn ? snapshot :
                        #"{"type":"error","message":"command requires authentication"}"#, connection)
                } else if command == "get_auth_state" {
                    self.sendAuth(connection)
                }
                self.receive(connection)
            }
        }
    }

    func sendAuth(_ connection: NWConnection) {
        send("{\"type\":\"auth_state\",\"logged_in\":\(loggedIn),\"is_active\":true,\"device_name\":\"Test\"}", connection)
    }

    func send(_ text: String, _ connection: NWConnection) {
        let context = NWConnection.ContentContext(identifier: "text", metadata: [NWProtocolWebSocket.Metadata(opcode: .text)])
        connection.send(content: Data(text.utf8), contentContext: context, isComplete: true, completion: .idempotent)
    }

    func stop() {
        connections.forEach { $0.cancel() }
        listener.cancel()
    }
}

@MainActor
private final class CoverServer {
    let listener: NWListener
    var connections: [NWConnection] = []
    var requests: [String] = []
    var port: Int { Int(listener.port!.rawValue) }

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                guard let self else { return }
                self.connections.append(connection)
                connection.start(queue: .main)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                    Task { @MainActor in
                        guard let data, let request = String(data: data, encoding: .utf8) else { return }
                        self.requests.append(request.components(separatedBy: " ")[1])
                        if self.requests.count == 1 { return }
                        let status = self.requests.last == "/failed" ? "500 Failure" : "200 OK"
                        let response = "HTTP/1.1 \(status)\r\nContent-Length: 5\r\nConnection: close\r\n\r\ncover"
                        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                            connection.cancel()
                        })
                    }
                }
            }
        }
        listener.start(queue: .main)
    }

    func stop() {
        connections.forEach { $0.cancel() }
        listener.cancel()
    }
}

@main
struct SoloistSourceTest {
    @MainActor
    static func wait(line: UInt = #line, _ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        fatalError("Timed out waiting for loopback at line \(line)")
    }

    @MainActor
    static func main() async throws {
        let now = Date(timeIntervalSince1970: 5)
        guard case .state(let track?, _) = try SoloistProtocol.parse(snapshot, now: now) else { fatalError("Missing state") }
        precondition(track.artist == "Massive Attack" && track.album == "Mezzanine")
        precondition(track.duration == 331 && track.elapsed == 134 && track.stamp.timeIntervalSince1970 == 1)
        precondition(track.origin == .soloist && track.app == "Spotify" && track.bundleID == nil)
        let coverFields = #"""
        "visual_identity":{"cover":[{"size":"default","url":"https://example.com/cover"}]},
        "playback":{"duration_ms":331000}
        """#
        let decorated = snapshot.replacingOccurrences(of: #""playback":{"duration_ms":331000}"#, with: coverFields)
        guard case .state(_, let cover) = try SoloistProtocol.parse(decorated, now: now) else {
            fatalError("Missing decorated state")
        }
        precondition(cover?.absoluteString == "https://example.com/cover")
        for level in [-1.0, 2.0] {
            let encoded = try SoloistProtocol.encode(.volume(level), isPlaying: false)
            let object = try JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any]
            precondition(object?["volume"] as? Int == (level < 0 ? 0 : 100))
        }
        for event in ["track_changed", "position_sync", "queue_changed", "playback_changed"] {
            let parsed = try SoloistProtocol.parse("{\"type\":\"\(event)\"}", now: now)
            precondition(parsed == .changed)
        }
        let idle = try SoloistProtocol.parse(#"{"type":"playback_state","status":"idle"}"#, now: now)
        precondition(idle == .state(nil, cover: nil))
        do { _ = try SoloistProtocol.parse("bad json", now: now); fatalError("Accepted invalid JSON") } catch {}
        let commands: [(PlayerCommand, String)] = [(.play, "play"), (.pause, "pause"), (.next, "skip_next"),
            (.previous, "skip_prev"), (.togglePlayPause, "pause"), (.seek(12.5), "seek"), (.volume(0.3), "set_volume")]
        for (command, name) in commands {
            let data = Data(try SoloistProtocol.encode(command, isPlaying: true).utf8)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                fatalError("Invalid encoded command")
            }
            precondition(object["command"] as? String == name && object["type"] as? String == "command")
            if case .seek = command { precondition(object["position_ms"] as? Int == 12500) }
            if case .volume = command { precondition(object["volume"] as? Int == 30) }
        }
        let server = try Server()
        defer { server.stop() }
        try await wait { server.listener.port != nil && server.port > 0 }
        let source = SoloistSource()
        var changes = 0
        source.watch { changes += 1 }
        source.connect(port: server.port)
        try await wait { source.authState?.loggedIn == false && server.commands.count == 2 }
        try await wait {
            if case .command("command requires authentication") = source.failure { return true }
            return false
        }
        let loggedOut = try await source.read()
        precondition(loggedOut == nil)
        server.loggedIn = true
        server.sendAuth(server.connections[0])
        try await wait { changes >= 5 && server.commands.count == 3 }
        let received = try await source.read()
        precondition(received == track)
        precondition(changes >= 2)
        commands.forEach { source.send($0.0) }
        try await wait { server.commands.count == 10 }
        precondition(Array(server.commands.dropFirst(3)) == commands.map(\.1))
        server.send(#"{"type":"queue_changed"}"#, server.connections[0])
        try await wait { server.commands.count == 11 }
        precondition(server.commands.last == "get_state")
        let coverServer = try CoverServer()
        defer { coverServer.stop() }
        try await wait { coverServer.listener.port != nil && coverServer.port > 0 }
        func coverSnapshot(_ name: String) -> String {
            let fields = """
            "visual_identity":{"cover":[{"url":"http://127.0.0.1:\(coverServer.port)/\(name)"}]},
            "playback":{"duration_ms":331000}
            """
            return snapshot.replacingOccurrences(of: #""playback":{"duration_ms":331000}"#, with: fields)
        }
        server.send(coverSnapshot("A"), server.connections[0])
        try await wait { coverServer.requests == ["/A"] }
        server.send(coverSnapshot("B"), server.connections[0])
        try await wait { coverServer.requests == ["/A", "/B"] }
        server.send(coverSnapshot("A"), server.connections[0])
        try await wait { coverServer.requests == ["/A", "/B", "/A"] }
        for _ in 0..<500 {
            if try await source.read()?.artwork == Data("cover".utf8) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let artwork = try await source.read()?.artwork
        precondition(artwork == Data("cover".utf8))
        server.send(coverSnapshot("failed"), server.connections[0])
        try await wait {
            if case .artwork = source.failure { return true }
            return false
        }
        for _ in 0..<5 { server.send(coverSnapshot("failed"), server.connections[0]) }
        try await Task.sleep(for: .milliseconds(200))
        precondition(coverServer.requests.filter { $0 == "/failed" }.count == 1)
        server.connections[0].cancel()
        try await wait { !source.isConnected }
        let lost = try await source.read()
        precondition(lost == nil && source.authState == nil)
        guard case .connection = source.failure else { preconditionFailure("Expected connection failure") }
        try await wait { server.connections.count == 2 && source.isConnected }
        source.connect(port: nil)
        let disconnected = try await source.read()
        precondition(disconnected == nil && source.authState == nil)
        source.unwatch()
        print("PASS: Soloist protocol, commands, loopback, reconnect and disconnect")
    }
}
