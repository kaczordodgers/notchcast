import Foundation

@main
@MainActor
struct AgentRegistryTests {
    static func check(_ value: Bool, _ message: String = "check failed") {
        precondition(value, message)
    }

    static func main() async throws {
        let index = AgentActionIndex()
        var runs = 0
        var available = true
        var completions = 0
        index.didComplete = { _, _ in completions += 1 }
        let action = AgentAction(id: "fixture.volume", title: "Fixture", parameters: .init(
            properties: ["level": .init(kind: .number, minimum: 0, maximum: 1)], required: ["level"]), danger: .consent)
        let entry = AgentActionIndex.Entry(action: action, isAvailable: { available }, run: { parameters in
            runs += 1
            return parameters
        })
        try index.register(entry)
        do {
            try index.register(entry)
            preconditionFailure("duplicate action accepted")
        } catch { check(error as? AgentReply.Code == .badRequest) }
        let provider = AgentActionIndex.StateProvider(id: "fixture.state", title: "State", read: { .bool(true) })
        try index.register(provider)
        do {
            try index.register(provider)
            preconditionFailure("duplicate state accepted")
        } catch { check(error as? AgentReply.Code == .badRequest) }
        check(index.actionIDs == [action.id] && index.stateIDs == [provider.id])
        let request = AgentRequest(verb: .run, id: action.id, parameters: .object(["level": .number(0.5)]))
        check(await index.handle(request) == .init(code: .notRunning))
        index.start()
        check(await index.handle(request) == .init(code: .declined))
        check(runs == 0)
        var dryRun = request
        dryRun.dryRun = true
        check(await index.handle(dryRun) == .init(code: .ok, result: action.json(available: true)))
        check(runs == 0)
        index.authorize = { _, _ in {} }
        check(await index.handle(request) == .init(code: .ok, result: request.parameters))
        check(runs == 1)
        for parameters: AgentJSON in [.object([:]), .object(["level": .number(-0.1)]),
                                      .object(["level": .number(1.1)]), .object(["level": .bool(true)]),
                                      .object(["level": .number(0), "extra": .null]), .array([])] {
            var bad = request
            bad.parameters = parameters
            check(await index.handle(bad) == .init(code: .badRequest))
        }
        available = false
        check(await index.handle(request) == .init(code: .failed))
        check(await index.handle(dryRun) == .init(code: .failed))
        let listed = await index.handle(.init(verb: .list))
        guard case .object(let listing) = listed.result, case .array(let actions)? = listing["actions"] else {
            preconditionFailure("missing discovery data")
        }
        check(actions == [action.json(available: false)])
        available = true
        check(await index.handle(.init(verb: .get, id: provider.id)) == .init(code: .ok, result: .bool(true)))
        check(await index.handle(.init(verb: .get, id: "missing")) == .init(code: .badRequest))
        check(await index.handle(.init(verb: .audit)) == .init(code: .failed))
        index.readAudit = { .array([.string("injected")]) }
        check(await index.handle(.init(verb: .audit)) == .init(code: .ok, result: .array([.string("injected")])))
        check(await index.handle(.init(verb: .status, id: "unexpected")) == .init(code: .badRequest))
        check(await index.handle(.init(verb: .get, id: provider.id, dryRun: true)) == .init(code: .badRequest))

        var approval: CheckedContinuation<(@MainActor () -> Void)?, Never>?
        index.authorize = { _, _ in await withCheckedContinuation { approval = $0 } }
        let stale = Task { await index.handle(request) }
        while approval == nil { await Task.yield() }
        index.stop()
        index.start()
        approval?.resume(returning: {})
        check(await stale.value == .init(code: .notRunning))
        check(runs == 1, "stale approval executed an action")

        approval = nil
        let disabled = Task { await index.handle(request) }
        while approval == nil { await Task.yield() }
        available = false
        approval?.resume(returning: {})
        check(await disabled.value == .init(code: .failed))
        check(runs == 1)

        available = true
        approval = nil
        let cancelled = Task { await index.handle(request) }
        while approval == nil { await Task.yield() }
        cancelled.cancel()
        approval?.resume(returning: {})
        check(await cancelled.value == .init(code: .failed))
        check(runs == 1)

        let harmless = AgentAction(id: "fixture.safe", title: "Safe", danger: .harmless)
        let safeIndex = AgentActionIndex()
        try safeIndex.register(.init(action: harmless, run: { _ in .string("dispatched") }))
        safeIndex.start()
        check(await safeIndex.handle(.init(verb: .run, id: harmless.id)) == .init(code: .ok, result: .string("dispatched")))
        let integer = AgentParameterSchema.Property(kind: .integer, minimum: 0, maximum: 10)
        check(integer.accepts(.number(10)) && !integer.accepts(.number(0.5)))
        check(!integer.accepts(.number(.infinity)))
        check(completions > 20)
        print("PASS: duplicate rejection, schemas, discovery, dry-run, consent/audit seams, stale approval and cancellation")
    }
}
