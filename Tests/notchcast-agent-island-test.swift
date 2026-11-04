// notchcast-sources: Tinycast/Features/AgentFleet/Island/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentFleet/Island/Service/*.swift
import Foundation

@MainActor
protocol NotchcastModule: AnyObject {
    func start()
    func stop()
}

@MainActor
final class FakeSource: AgentIslandSource {
    var snapshot = AgentIslandState.Snapshot(sourceID: "fixture")
}

@main
struct AgentIslandTest {
    @MainActor
    static func main() {
        let source = FakeSource()
        let module = AgentIslandModule()
        module.sources = [source]
        var now = 0.0
        func refresh(_ pointer: Bool = false) -> Bool { module.refresh(now: now, pointerInside: pointer) }
        func presentation() -> AgentIslandState.Presentation { module.state.presentations["fixture"]! }
        module.start()
        assert(refresh())
        assert(presentation().mode == .idle)
        source.snapshot.running = ["a", "b", "c", "d"]
        now = 1
        assert(refresh())
        assert(presentation().agents == ["a", "b", "c"])
        now = 1.649
        _ = refresh()
        assert(!presentation().peek)
        now = 1.65
        _ = refresh()
        assert(presentation().peek)
        source.snapshot.unreadCount = 4
        source.snapshot.latest = "Synthetic message"
        _ = refresh()
        assert(presentation().mode == .message && presentation().unreadCount == 4)
        assert(presentation().latest == "Synthetic message")
        source.snapshot.takeover = true
        _ = refresh()
        assert(presentation().mode == .takeover)
        source.snapshot.questions = 3
        _ = refresh()
        assert(presentation().mode == .question && presentation().remaining == 3)
        source.snapshot.questions = 2
        _ = refresh()
        assert(presentation().remaining == 2)
        source.snapshot.approvals = 2
        _ = refresh()
        assert(presentation().mode == .approval && presentation().remaining == 2)
        source.snapshot.approvals = 1
        _ = refresh()
        assert(presentation().remaining == 1)
        source.snapshot.failureID = "failure"
        _ = refresh()
        assert(presentation().mode == .failed)
        source.snapshot = .init(sourceID: "fixture")
        now = 100
        _ = refresh()
        assert(presentation().mode == .failed)
        var routed: [AgentIslandAction] = []
        module.handleAction = { routed.append($0) }
        let kinds: [AgentIslandAction.Kind] = [.openApp, .openAgent("a"), .openMessage("m"),
            .sendMessage(agentID: "a", text: "Fixture"), .stopAgent("a"), .reviewAttention,
            .respondApproval(id: "p", accepted: true), .answerPrompt(id: "q", answer: "Fixture"),
            .dismissFailure]
        for kind in kinds { module.route(.init(sourceID: "fixture", kind: kind)) }
        assert(routed.map(\.kind) == kinds)
        _ = refresh()
        assert(presentation().finished)
        now = 105.199
        _ = refresh()
        assert(presentation().finished)
        now = 105.2
        _ = refresh(true)
        assert(presentation().finished)
        _ = refresh()
        assert(presentation().mode == .idle)
        now = 106
        source.snapshot.questions = 1
        assert(refresh())
        now = 106.299
        source.snapshot.questions = 2
        assert(!refresh())
        now = 106.3
        source.snapshot.questions = 3
        assert(refresh())
        module.sources = []
        _ = refresh(true)
        assert(!module.state.presentations.isEmpty)
        _ = refresh()
        assert(module.state.presentations.isEmpty)
        let second = FakeSource()
        second.snapshot = .init(sourceID: "second", running: ["other"])
        module.sources = [source, second]
        _ = refresh()
        assert(module.state.presentations.count == 2)
        assert(module.state.presentations["second"]?.mode == .working)
        assert(module.state.presentations["fixture"]?.mode == .question)
        module.sources = []
        module.route(.init(sourceID: "fixture", kind: .openApp))
        assert(routed.count == kinds.count)
        module.stop()
        assert(!refresh())
        print("Agent island: all checks passed")
    }
}
