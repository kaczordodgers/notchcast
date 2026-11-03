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
                    self.send(snapshot, connection)
                    self.send(#"{"type":"auth_state","logged_in":true,"is_active":true,"device_name":"Test"}"#, connection)
                }
                self.receive(connection)
            }
        }
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

@main
struct SoloistSourceTest {
    @MainActor
    static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        fatalError("Timed out waiting for loopback")
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
        try await wait { server.listener.port != nil }
        let source = SoloistSource()
        var changes = 0
        source.watch { changes += 1 }
        source.connect(port: server.port)
        try await wait { source.authState?.loggedIn == true }
        let received = try await source.read()
        precondition(received == track)
        precondition(changes >= 2)
        commands.forEach { source.send($0.0) }
        try await wait { server.commands.count == 8 }
        precondition(Array(server.commands.dropFirst()) == commands.map(\.1))
        server.send(#"{"type":"queue_changed"}"#, server.connections[0])
        try await wait { server.commands.count == 9 }
        precondition(server.commands.last == "get_state")
        server.connections[0].cancel()
        try await wait { !source.isConnected }
        let retained = try await source.read()
        precondition(retained == received)
        try await wait { server.connections.count == 2 && source.isConnected }
        source.connect(port: nil)
        let disconnected = try await source.read()
        precondition(disconnected == nil && source.authState == nil)
        source.unwatch()
        print("PASS: Soloist protocol, commands, loopback, reconnect and disconnect")
    }
}
