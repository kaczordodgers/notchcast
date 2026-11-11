// notchcast-sources: Tinycast/Features/AgentBridge/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentBridge/Service/*.swift
// notchcast-sources: Tinycast/Features/AgentConsent/Model/*.swift
import Foundation

@main
@MainActor
struct AgentDeviceTests {
    final class FakeBackend: AgentDeviceBackend {
        let deviceName: String
        let operations: [(name: String, parameters: AgentParameterSchema)]
        var isAvailable = true

        init(_ deviceName: String, _ operations: [(name: String, parameters: AgentParameterSchema)]) {
            self.deviceName = deviceName
            self.operations = operations
        }
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
        let speed = AgentParameterSchema.Property(kind: .number, minimum: 1, maximum: 6)
        let channel = AgentParameterSchema.Property(kind: .integer, allowedValues: [0, 1, 2, 5, 6].map { .number($0) })
        let treadmill = FakeBackend("treadmill", [
            ("start", .init(properties: ["speed": speed, "minutes": .init(kind: .integer, minimum: 0, maximum: 1092)],
                            required: ["speed", "minutes"])),
            ("stop", .init()), ("pause", .init()), ("resume", .init()),
            ("speed", .init(properties: ["speed": speed], required: ["speed"])),
        ])
        let katana = FakeBackend("katana", [
            ("channel", .init(properties: ["channel": channel], required: ["channel"])),
            ("tone", .init(properties: ["toneID": .init(kind: .string, minimumLength: 1), "channel": channel],
                           required: ["toneID", "channel"])),
        ])
        try AgentDeviceActions.register(treadmill, in: index)
        try AgentDeviceActions.register(katana, in: index)
        index.start()
        var audited: [AgentReply.Code] = []
        index.didComplete = { request, reply in
            if request.verb == .run, !request.dryRun { audited.append(reply.code) }
        }
        index.authorize = { action, _ in
            let allowed = AgentConsentPolicy.decide(agentID: "local-cli", actionID: action.id,
                danger: .dangerous,
                grants: [.init(agentID: "local-cli", actionID: action.id, expiresAt: nil)],
                now: Date()) == .allow
            guard allowed else { return nil }
            return {}
        }
        precondition(index.actionIDs.count == 7 && index.stateIDs.count == 2)
        let start = AgentRequest(verb: .run, id: "device.treadmill.start",
                                 parameters: .object(["speed": .number(4), "minutes": .number(30)]))
        let denied = await index.handle(start)
        precondition(denied.code == .declined && treadmill.calls.isEmpty)
        precondition(audited == [.declined])
        var dry = start
        dry.dryRun = true
        let discovery = await index.handle(dry)
        precondition(discovery.code == .ok && treadmill.calls.isEmpty)
        precondition(audited == [.declined])
        guard case .object(let fields) = discovery.result else { preconditionFailure() }
        precondition(fields["danger"] == .string("dangerous"))
        index.authorize = { action, _ in
            guard action.danger == .dangerous else { return nil }
            return {}
        }
        let approved = await index.handle(start)
        precondition(approved.code == .ok && treadmill.calls == ["start"])
        precondition(audited == [.declined, .ok])
        for parameters: AgentJSON in [.object([:]), .object(["speed": .number(0)]),
                                      .object(["speed": .number(7)]),
                                      .object(["speed": .number(4), "raw": .string("packet")])] {
            let reply = await index.handle(.init(verb: .run, id: "device.treadmill.speed", parameters: parameters))
            precondition(reply.code == .badRequest)
        }
        var consentCalls = 0
        index.authorize = { _, _ in consentCalls += 1; return {} }
        for dryRun in [false, true] {
            for channel in [3.0, 4.0, 7.0, 1.5] {
                for operation in ["channel", "tone"] {
                    var fields: [String: AgentJSON] = ["channel": .number(channel)]
                    if operation == "tone" { fields["toneID"] = .string("fixture") }
                    let reply = await index.handle(.init(verb: .run, id: "device.katana.\(operation)",
                        parameters: .object(fields), dryRun: dryRun))
                    precondition(reply.code == .badRequest && katana.calls.isEmpty)
                }
            }
            let emptyTone = await index.handle(.init(verb: .run, id: "device.katana.tone",
                parameters: .object(["toneID": .string(""), "channel": .number(1)]), dryRun: dryRun))
            precondition(emptyTone.code == .badRequest && katana.calls.isEmpty)
        }
        precondition(consentCalls == 0)
        let tone = AgentRequest(verb: .run, id: "device.katana.tone",
                                parameters: .object(["toneID": .string("fixture"), "channel": .number(1)]))
        let written = await index.handle(tone)
        precondition(written.code == .ok && katana.calls == ["tone"])
        katana.fail = true
        let failed = await index.handle(tone)
        precondition(failed.code == .failed && katana.calls == ["tone"])
        index.authorize = { _, _ in
            treadmill.isAvailable = false
            return {}
        }
        let disconnected = await index.handle(start)
        precondition(disconnected.code == .failed && treadmill.calls == ["start"])
        let state = await index.handle(.init(verb: .get, id: "device.katana"))
        precondition(state.code == .ok)
        index.stop()
        let stopped = await index.handle(tone)
        precondition(stopped.code == .notRunning)
        AgentDeviceActions.unregister(katana, from: index)
        precondition(index.actionIDs.count == 5 && index.stateIDs == ["device.treadmill"])
        print("Agent device tests passed (fake backends only)")
    }
}
