// notchcast-sources: Tinycast/Features/AgentAnswer/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentAnswer/Service/AgentAnswerModule.swift
// notchcast-sources: Tinycast/Features/AgentAnswer/Service/AgentAnswerTransport.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
import Foundation

@MainActor
final class FakeTransport: AgentAnswerTransport {
    var result: AgentAnswerResult = .sent
    var calls = 0
    var fails = false
    var duringSend: (() async -> Void)?

    func send(_ answer: AgentAnswer, to item: AgentAnswerItem) async throws -> AgentAnswerResult {
        calls += 1
        await duringSend?()
        if fails { throw NSError(domain: "test", code: 1) }
        return result
    }
}

@main
struct AgentAnswerTests {
    @MainActor
    static func main() async {
        let suite = "agent-answer-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let module = AgentAnswerModule()
        let controller = NotchcastModuleController([
            .init(requires: [.agentAnswer], module: module)
        ], preferences: preferences)
        controller.run()
        precondition(!preferences.isOn(.agentAnswer) && !module.isRunning)
        preferences.set(.agentAnswer, true)
        controller.run()
        precondition(module.isRunning)
        let transport = FakeTransport()
        let item = AgentAnswerItem(id: "thread", revision: "question-1", source: .bot,
                                   question: "Proceed?", choices: ["yes"], allowsApprove: true,
                                   allowsDeny: true)
        func check(_ answer: AgentAnswer, _ expected: AgentAnswerResult,
                   item target: AgentAnswerItem? = nil) async {
            let result = await module.answer(answer, item: target ?? item, transport: transport)
            precondition(result == expected, "Expected \(expected), got \(result)")
        }
        await check(.reply(" \n"), .invalidAnswer)
        await check(.choice("missing"), .invalidAnswer)
        let t3 = AgentAnswerItem(id: "t3", revision: "1", source: .t3, question: "Reply?",
                                choices: ["yes"], allowsApprove: true, allowsDeny: true)
        await check(.approve, .invalidAnswer, item: t3)
        await check(.deny, .invalidAnswer, item: t3)
        await check(.choice("yes"), .invalidAnswer, item: t3)
        precondition(transport.calls == 0)
        for result in [AgentAnswerResult.relink, .gone, .stale] {
            transport.result = result
            await check(.reply("ok"), result)
        }
        transport.fails = true
        let failed = await module.answer(.approve, item: item, transport: transport)
        guard case .failed = failed else { fatalError("Error lost") }
        transport.fails = false
        transport.result = .queued
        transport.duringSend = {
            await check(.deny, .inProgress)
        }
        await check(.choice("yes"), .queued)
        let calls = transport.calls
        await check(.approve, .alreadyAnswered)
        precondition(transport.calls == calls)
        transport.duringSend = nil
        transport.result = .sent
        await check(.reply("ok"), .sent, item: t3)
        preferences.set(.agentAnswer, false)
        controller.run()
        precondition(!module.isRunning)
        await check(.reply("ok"), .disabled)
        module.start()
        await check(.reply("ok"), .alreadyAnswered, item: t3)
        let next = AgentAnswerItem(id: "thread", revision: "question-2", source: .bot, question: "Next?")
        transport.duringSend = { module.stop() }
        await check(.reply("ok"), .cancelled, item: next)
        module.start()
        await check(.reply("ok"), .alreadyAnswered, item: next)
        print("AgentAnswer checks passed")
    }
}
