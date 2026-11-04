// notchcast-sources: -swift-version 6 -strict-concurrency=complete
// notchcast-sources: Tinycast/Features/AgentChatTools/Service/AgentChatToolsModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/MCP/Model/MCPServer.swift
// notchcast-sources: Tinycast/Features/AI/Model/AIToolServer.swift
import Foundation
import Observation

enum NotchcastFeature { case agentChatTools }

@MainActor @Observable
final class NotchcastPreferences {
    var enabled = false
    func isOn(_ feature: NotchcastFeature) -> Bool { enabled }
}

@MainActor
final class MCPSettingsStore {
    var servers: [MCPServer] = []
    func server(id: UUID) -> MCPServer? { servers.first { $0.id == id } }
    func save(_ server: MCPServer) {
        remove(id: server.id)
        servers.append(server)
    }
    func remove(id: UUID) { servers.removeAll { $0.id == id } }
}

@main
struct ChatModuleTest {
    @MainActor static func main() async {
        let suite = "chat-module-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MCPSettingsStore()
        var installed = false
        var changes = 0
        let module = AgentChatToolsModule(store: store, binaryPath: "/fixture/notchcast",
            isBinaryInstalled: { installed }, onChange: { changes += 1 }, defaults: defaults)
        let preferences = NotchcastPreferences()
        let controller = NotchcastModuleController([
            .init(requires: [.agentChatTools], module: module)
        ], preferences: preferences)
        controller.run()
        precondition(!module.isRunning && module.add() == .disabled)
        preferences.enabled = true
        for _ in 0..<20 { await Task.yield() }
        precondition(module.isRunning && module.add() == .binaryMissing)
        precondition(store.servers.isEmpty && changes == 0)
        installed = true
        precondition(module.add() == .added && module.isAdded && changes == 1)
        let id = AgentChatToolsModule.serverID
        precondition(store.server(id: id)?.transport == .stdio(
            command: "/fixture/notchcast", arguments: ["mcp"], environmentKeys: []))
        precondition(store.server(id: id)?.trust == .ask)
        precondition(module.add() == .added && changes == 1)
        preferences.enabled = false
        for _ in 0..<20 { await Task.yield() }
        precondition(!module.isRunning && store.server(id: id)?.isEnabled == false)
        preferences.enabled = true
        for _ in 0..<20 { await Task.yield() }
        precondition(module.isRunning && store.server(id: id)?.isEnabled == true)
        module.remove()
        precondition(!module.isAdded && store.servers.isEmpty && changes == 4)
        print("PASS fake settings, switch lifecycle, add action, missing binary result and removal")
    }
}
