// notchcast-sources: Tinycast/Features/AgentAnswer/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentAnswer/Service/AgentAnswerModule.swift
// notchcast-sources: Tinycast/Features/AgentAnswer/Service/AgentAnswerTransport.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift

import Foundation

@MainActor
final class ModuleTransport: AgentAnswerTransport {
    var calls = 0
    var fails = false
    func send(_ answer: AgentAnswer, to item: AgentAnswerItem) async throws -> AgentAnswerResult {
        calls += 1
        if fails { throw NSError(domain: "fixture", code: 1,
                                 userInfo: [NSLocalizedDescriptionKey: "Fake delivery failed"]) }
        return .sent
    }
}

@main
struct AgentAnswerModuleTest {
    @MainActor static func main() async {
        let suite = "answer-module-\(UUID())"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let module = AgentAnswerModule()
        let controller = NotchcastModuleController([
            .init(requires: [.agentAnswer], module: module)], preferences: preferences)
        controller.run()
        precondition(!module.isRunning)
        preferences.set(.agentAnswer, true)
        for _ in 0..<1000 where !module.isRunning { await Task.yield() }
        precondition(module.isRunning)
        let transport = ModuleTransport()
        let item = AgentAnswerItem(id: "fixture", revision: "1", source: .bot, question: "Reply?")
        transport.fails = true
        let failure = await module.answer(.reply("hello"), item: item, transport: transport)
        precondition(failure == .failed("Fake delivery failed"))
        transport.fails = false
        let success = await module.answer(.reply("hello"), item: item, transport: transport)
        precondition(success == .sent && transport.calls == 2)
        preferences.set(.agentAnswer, false)
        for _ in 0..<1000 where module.isRunning { await Task.yield() }
        precondition(!module.isRunning)
        let disabled = await module.answer(.reply("hello"), item: item, transport: transport)
        precondition(disabled == .disabled && transport.calls == 2)
        print("PASS: observed switches, answer dispatch, exact failure and disabled transport")
    }
}
