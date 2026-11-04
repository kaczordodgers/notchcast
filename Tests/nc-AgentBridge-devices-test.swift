import Foundation

@main
@MainActor
struct AgentDeviceTests {
    final class FakeBackend: AgentDeviceBackend {
        var isAvailable = true
        var calls: [String] = []
        var fail = false

        func readState() async throws -> AgentJSON { .object(["connected": .bool(isAvailable)]) }

        func perform(_ operation: String, parameters: AgentJSON) async throws -> AgentJSON {
            if fail { throw AgentReply.Code.failed }
            calls.append(operation)
            return parameters
        }
    }

    static func main() async throws {
        let index = AgentActionIndex()
        let treadmill = FakeBackend()
        let katana = FakeBackend()
        try AgentDeviceActions.register(.treadmill, backend: treadmill, in: index)
        try AgentDeviceActions.register(.katana, backend: katana, in: index)
        index.start()
        precondition(index.actionIDs.count == 7 && index.stateIDs.count == 2)
        let start = AgentRequest(verb: .run, id: "device.treadmill.start",
                                 parameters: .object(["speed": .number(4), "minutes": .number(30)]))
        let denied = await index.handle(start)
        precondition(denied.code == .declined && treadmill.calls.isEmpty)
        var dry = start
        dry.dryRun = true
        let discovery = await index.handle(dry)
        precondition(discovery.code == .ok && treadmill.calls.isEmpty)
        guard case .object(let fields) = discovery.result else { preconditionFailure() }
        precondition(fields["danger"] == .string("dangerous"))
        index.authorize = { action, _ in action.danger == .dangerous }
        let approved = await index.handle(start)
        precondition(approved.code == .ok && treadmill.calls == ["start"])
        for parameters: AgentJSON in [.object([:]), .object(["speed": .number(0)]),
                                      .object(["speed": .number(7)]),
                                      .object(["speed": .number(4), "raw": .string("packet")])] {
            let reply = await index.handle(.init(verb: .run, id: "device.treadmill.speed", parameters: parameters))
            precondition(reply.code == .badRequest)
        }
        for channel in [3.0, 4.0, 7.0, 1.5] {
            let reply = await index.handle(.init(verb: .run, id: "device.katana.channel",
                                                parameters: .object(["channel": .number(channel)])))
            precondition(reply.code == .badRequest && katana.calls.isEmpty)
        }
        let tone = AgentRequest(verb: .run, id: "device.katana.tone",
                                parameters: .object(["toneID": .string("fixture"), "channel": .number(1)]))
        let written = await index.handle(tone)
        precondition(written.code == .ok && katana.calls == ["tone"])
        katana.fail = true
        let failed = await index.handle(tone)
        precondition(failed.code == .failed && katana.calls == ["tone"])
        index.authorize = { _, _ in
            treadmill.isAvailable = false
            return true
        }
        let disconnected = await index.handle(start)
        precondition(disconnected.code == .failed && treadmill.calls == ["start"])
        let state = await index.handle(.init(verb: .get, id: "device.katana"))
        precondition(state.code == .ok)
        index.stop()
        let stopped = await index.handle(tone)
        precondition(stopped.code == .notRunning)
        print("Agent device tests passed (fake backends only)")
    }
}
