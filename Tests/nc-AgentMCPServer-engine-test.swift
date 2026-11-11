// notchcast-sources: Tinycast/Features/AgentMCPServer/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentMCPServer/Service/AgentMCPModule.swift
// notchcast-kit: core
import Foundation

@MainActor
final class FakeBackend: AgentMCPBackend {
    var calls = 0
    var onRead: (() -> Void)?
    func actions() async throws -> [AgentMCPAction] {
        ["agents.list", "agents.send", "agents.wait", "agents.interrupt", "agents.approve",
         "agents.remember", "data.delete", "credentials.change"].map {
            .init(id: $0, title: $0, inputSchema: Data(#"{"type":"object"}"#.utf8), danger: "consent", isDestructive: true)
        }
    }
    func call(_ id: String, arguments: Data) async throws -> Data {
        calls += 1
        return arguments
    }
    func states() async throws -> [AgentMCPState] {
        [.init(id: "agents.list", title: "Sessions"), .init(id: "credentials", title: "Secrets")]
    }
    func readState(_ id: String) async throws -> Data {
        onRead?()
        return Data("{}".utf8)
    }
}

@main
struct EngineTest {
    @MainActor
    static func main() async throws {
        let backend = FakeBackend()
        let module = AgentMCPModule(backend: backend)
        let suite = "test.mcp." + UUID().uuidString
        let preferences = NotchcastPreferences(suiteName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        precondition(!preferences.isOn(.agentMCPServer))
        let controller = NotchcastModuleController([
            .init(requires: [.agentMCPServer], module: module)
        ], preferences: preferences)
        controller.run()
        precondition(!module.engine.isRunning)
        preferences.set(.agentMCPServer, true)
        for _ in 0..<10 { await Task.yield() }
        precondition(module.engine.isRunning)
        func send(_ method: String, _ params: String = "{}", id: String = "1") async -> String {
            let line = "{\"jsonrpc\":\"2.0\",\"id\":\(id),\"method\":\"\(method)\",\"params\":\(params)}"
            return String(bytes: await module.engine.receive(line: Data(line.utf8)) ?? Data(), encoding: .utf8)!
        }
        let malformed = await module.engine.receive(line: Data("no".utf8))!
        precondition(String(bytes: malformed, encoding: .utf8)!.contains("-32700"))
        let invalid = await module.engine.receive(line: Data("[]".utf8))!
        precondition(String(bytes: invalid, encoding: .utf8)!.contains("-32600"))
        let early = await send("tools/list")
        precondition(early.contains("-32002"))
        let infiniteID = await send("ping", id: "-1e999")
        precondition(infiniteID.contains("-32600"))
        let initializeParams = #"{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1"}}"#
        let initialized = await send("initialize", initializeParams)
        precondition(initialized.contains("2025-06-18"))
        let initialization = Data(("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":"
            + initializeParams + "}").utf8)
        for number in 0..<65 {
            let response = await module.engine.receive(line: initialization, session: "client-\(number)")!
            precondition(String(bytes: response, encoding: .utf8)!.contains("serverInfo"))
        }
        let listing = Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#.utf8)
        let evicted = await module.engine.receive(line: listing, session: "client-0")!
        precondition(String(bytes: evicted, encoding: .utf8)!.contains("Initialize first"))
        _ = await module.engine.receive(line: initialization)
        print("PASS 65 initializes succeed and least recently used session is evicted")
        let tools = await send("tools/list", id: #""request""#)
        precondition(tools.contains("inputSchema") && tools.contains("annotations"))
        precondition(tools.contains("approve") && tools.contains("delete"))
        let badID = await send("ping", id: "true")
        precondition(badID.contains("-32600"))
        let badArguments = await send("tools/call", #"{"name":"agents.send","arguments":true}"#)
        precondition(badArguments.contains("-32602"))
        let infiniteArguments = await send("tools/call", #"{"name":"agents.send","arguments":{"nested":[-1e999]}}"#)
        precondition(infiniteArguments.contains("-32602"))
        for action in ["agents.list", "agents.send", "agents.wait", "agents.interrupt"] {
            let result = await send("tools/call", "{\"name\":\"\(action)\",\"arguments\":{\"text\":\"hello\"}}")
            precondition(result.contains("hello") && result.hasSuffix("\n"))
        }
        for action in ["agents.approve", "agents.remember"] {
            let result = await send("tools/call", "{\"name\":\"\(action)\"}")
            precondition(result.contains("content"))
        }
        precondition(backend.calls == 6)
        let unregistered = await send("tools/call", #"{"name":"unregistered"}"#)
        precondition(unregistered.contains("Unknown tool") && backend.calls == 6)
        let unknown = await send("unknown")
        precondition(unknown.contains("-32601"))
        let notification = await module.engine.receive(line: Data(#"{"jsonrpc":"2.0","method":"unknown"}"#.utf8))
        precondition(notification == nil)
        let resources = await send("resources/list")
        precondition(resources.contains("agents.list"))
        precondition(resources.contains("Secrets"))
        let refusedState = await send("resources/read", #"{"uri":"notchcast-state:unregistered"}"#)
        precondition(refusedState.contains("-32602"))
        let state = await send("resources/read", #"{"uri":"notchcast-state:agents.list"}"#)
        precondition(state.contains("contents") && state.contains("application"))
        backend.onRead = { module.stop(); module.start() }
        let stale = await send("resources/read", #"{"uri":"notchcast-state:agents.list"}"#)
        precondition(stale.contains("-32603"))
        preferences.set(.agentMCPServer, false)
        for _ in 0..<10 { await Task.yield() }
        precondition(!module.engine.isRunning)
        print("PASS: protocol, params, resources, boundary, stale results and switch lifecycle")
    }
}
