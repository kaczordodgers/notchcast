// notchcast-sources: -swift-version 6 -strict-concurrency=complete
// notchcast-sources: Tinycast/Features/AgentMCPServer/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentMCPServer/Service/AgentMCPModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
import Foundation
import Observation

enum NotchcastFeature { case agentMCPServer }

@MainActor @Observable
final class NotchcastPreferences {
    var enabled = false
    func isOn(_ feature: NotchcastFeature) -> Bool { enabled }
}

@MainActor
final class ModuleBackend: AgentMCPBackend {
    var calls = 0
    var fails = false
    func actions() async throws -> [AgentMCPAction] {
        [.init(id: "agents.list", title: "Fixture", inputSchema: Data(#"{"type":"object"}"#.utf8), danger: "harmless")]
    }
    func states() async throws -> [AgentMCPState] { [] }
    func call(_ id: String, arguments: Data) async throws -> Data {
        calls += 1
        if fails { throw CocoaError(.fileReadUnknown) }
        return Data("fixture result".utf8)
    }
    func readState(_ id: String) async throws -> Data { Data() }
}

@main
struct ModuleTest {
    @MainActor static func main() async {
        let backend = ModuleBackend()
        let module = AgentMCPModule(backend: backend)
        let preferences = NotchcastPreferences()
        let controller = NotchcastModuleController([
            .init(requires: [.agentMCPServer], module: module)
        ], preferences: preferences)
        controller.run()
        precondition(!module.engine.isRunning)
        preferences.enabled = true
        for _ in 0..<20 { await Task.yield() }
        precondition(module.engine.isRunning)
        func exchange(_ method: String, _ params: String) async -> String {
            let line = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"\(method)\",\"params\":\(params)}"
            let output = await module.engine.receive(line: Data(line.utf8))!
            precondition(output.last == 10)
            return String(bytes: output, encoding: .utf8)!
        }
        let initialized = await exchange("initialize", #"{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{}}"#)
        precondition(initialized.contains("serverInfo"))
        let result = await exchange("tools/call", #"{"name":"agents.list"}"#)
        precondition(result.contains("fixture result") && backend.calls == 1)
        backend.fails = true
        let failure = await exchange("tools/call", #"{"name":"agents.list"}"#)
        precondition(failure.contains("Operation failed") && failure.contains("-32603"))
        preferences.enabled = false
        for _ in 0..<20 { await Task.yield() }
        precondition(!module.engine.isRunning)
        let stopped = await exchange("tools/call", #"{"name":"agents.list"}"#)
        precondition(stopped.contains("Server stopped") && backend.calls == 2)
        print("PASS module switch lifecycle, fake transport action and failure response")
    }
}
