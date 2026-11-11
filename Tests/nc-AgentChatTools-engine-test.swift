// notchcast-sources: -swift-version 6 -strict-concurrency=complete
// notchcast-kit: core
// notchcast-sources: Tinycast/Features/AgentChatTools/Service/AgentChatToolsModule.swift
// notchcast-sources: Tinycast/Features/MCP/Settings/MCPSettingsStore.swift
// notchcast-sources: Tinycast/Features/MCP/Model/MCPServer.swift
// notchcast-sources: Tinycast/Features/Settings/AppSettingsKey.swift
// notchcast-sources: Tinycast/Features/AI/Model/AIToolServer.swift
import Foundation

@main
struct AgentChatToolsTest {
    @MainActor
    static func main() async {
        let suite = "agent-chat-tools-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MCPSettingsStore(defaults: defaults)
        let other = MCPServer(name: "Notchcast", slug: "notchcast", trust: .always)
        store.save(other)
        let original = store.servers
        let preferences = NotchcastPreferences(suiteName: suite)
        preferences.set(.agentChatTools, false)
        var installed = false
        let module = AgentChatToolsModule(store: store, binaryPath: "/test/notchcast",
            isBinaryInstalled: { installed }, defaults: defaults)
        let controller = NotchcastModuleController([
            .init(requires: [.agentChatTools], module: module)
        ], preferences: preferences)
        controller.run()
        precondition(module.add() == .disabled)
        preferences.set(.agentChatTools, true)
        await settle()
        precondition(module.isRunning)
        precondition(module.add() == .binaryMissing && store.servers == original)
        installed = true
        precondition(module.add() == .added && module.isAdded)
        let id = AgentChatToolsModule.serverID
        precondition(store.server(id: id)?.trust == .ask)
        precondition(store.server(id: id)?.transport == .stdio(
            command: "/test/notchcast", arguments: ["mcp"], environmentKeys: []))
        store.setTrust(.never, for: id)
        precondition(module.add() == .added && store.servers.count == 2)
        precondition(store.server(id: id)?.trust == .never)
        var customized = store.server(id: id)!
        customized.name = "Custom agent"
        customized.transport = .stdio(command: "/custom/agent", arguments: ["custom"], environmentKeys: [])
        customized.isEnabled = false
        store.save(customized)
        let saved = store.server(id: id)!
        module.start()
        precondition(store.server(id: id) == saved)
        precondition(module.add() == .added && store.server(id: id) == saved)
        module.stop()
        module.start()
        precondition(store.server(id: id) == saved)
        customized.isEnabled = true
        store.save(customized)
        preferences.set(.agentChatTools, false)
        await settle()
        precondition(!module.isRunning && store.server(id: id)?.isEnabled == false)
        preferences.set(.agentChatTools, true)
        await settle()
        precondition(store.server(id: id)?.isEnabled == true)
        precondition(store.server(id: id)?.name == "Custom agent")
        precondition(store.server(id: id)?.transport == customized.transport)
        installed = false
        module.stop()
        module.start()
        precondition(store.server(id: id)?.isEnabled == false)
        module.remove()
        module.remove()
        precondition(!module.isAdded && store.servers == original)
        precondition(MCPSettingsStore(defaults: defaults).servers == original)
        print("AgentChatTools: binary gate, idempotency, ownership, trust, persistence, switch lifecycle PASSED")
    }

    static func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }
}
