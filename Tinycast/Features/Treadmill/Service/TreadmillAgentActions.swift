import Foundation

extension TreadmillCoordinator: AgentDeviceBackend {
    func configure(index: AgentActionIndex) {
        agentIndex = index
        updateAgentRegistration()
    }

    func updateAgentRegistration() {
        guard let agentIndex else { return }
        unregisterAgentActions()
        guard walkEnabled else { return }
        do { try AgentDeviceActions.register(self, in: agentIndex) }
        catch { unregisterAgentActions() }
    }

    private func unregisterAgentActions() {
        if let agentIndex { AgentDeviceActions.unregister(self, from: agentIndex) }
    }

    var deviceName: String { "treadmill" }

    private enum Operation: String, CaseIterable {
        case start, stop, pause, resume, speed

        var parameters: AgentParameterSchema {
            let speed = AgentParameterSchema.Property(kind: .number, minimum: TreadmillProtocol.speedRange.lowerBound,
                                                      maximum: TreadmillProtocol.speedRange.upperBound)
            return switch self {
            case .start:
                .init(properties: ["speed": speed, "minutes": .init(kind: .integer, minimum: 0,
                    maximum: Double(TreadmillProtocol.maximumMinutes))], required: ["speed", "minutes"])
            case .speed: .init(properties: ["speed": speed], required: ["speed"])
            case .stop, .pause, .resume: .init()
            }
        }
    }

    var operations: [(name: String, parameters: AgentParameterSchema)] {
        Operation.allCases.map { ($0.rawValue, $0.parameters) }
    }

    var isAvailable: Bool { walkEnabled && isReady && connected }

    func readState() async throws -> AgentJSON {
        .object(["connected": .bool(connected), "walking": .bool(engine.walk != nil)])
    }

    func perform(_ operation: String, parameters: AgentJSON) async throws -> AgentJSON {
        guard walkEnabled else { throw TreadmillFailure.disabled }
        guard let operation = Operation(rawValue: operation), operation.parameters.accepts(parameters),
              case .object(let fields) = parameters else { throw AgentReply.Code.badRequest }
        switch operation {
        case .start:
            guard case .number(let speed)? = fields["speed"], case .number(let minutes)? = fields["minutes"]
            else { throw AgentReply.Code.badRequest }
            try startWalk(speed: speed, minutes: Int(minutes))
        case .stop: try stopWalk()
        case .pause: try pauseWalk()
        case .resume: try resumeWalk()
        case .speed:
            guard case .number(let speed)? = fields["speed"] else { throw AgentReply.Code.badRequest }
            try setSpeed(speed)
        }
        return try await readState()
    }
}
