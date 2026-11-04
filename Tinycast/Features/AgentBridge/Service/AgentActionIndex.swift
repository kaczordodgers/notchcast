import Foundation
import Observation

@MainActor
@Observable
final class AgentActionIndex {
    struct Entry {
        let action: AgentAction
        var isAvailable: @MainActor () -> Bool = { true }
        let run: @MainActor (AgentJSON) async throws -> AgentJSON
    }

    struct StateProvider {
        let id: String
        let title: String
        var isAvailable: @MainActor () -> Bool = { true }
        let read: @MainActor () async throws -> AgentJSON
    }

    private(set) var isRunning = false
    private(set) var actionIDs: [String] = []
    private(set) var stateIDs: [String] = []
    @ObservationIgnored private var actions: [String: Entry] = [:]
    @ObservationIgnored private var states: [String: StateProvider] = [:]
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored var authorize: @MainActor (AgentAction, AgentJSON) async -> Bool = { action, _ in
        action.danger == .harmless
    }
    @ObservationIgnored var didComplete: @MainActor (AgentRequest, AgentReply) async -> Void = { _, _ in }
    @ObservationIgnored var readAudit: (@MainActor () async throws -> AgentJSON)?
    @ObservationIgnored var receiveMCP: (@MainActor (AgentRequest) async throws -> AgentJSON)?

    func register(_ entry: Entry) throws {
        guard !entry.action.id.isEmpty, actions[entry.action.id] == nil else { throw AgentReply.Code.badRequest }
        actions[entry.action.id] = entry
        actionIDs = actions.keys.sorted()
    }

    func register(_ provider: StateProvider) throws {
        guard !provider.id.isEmpty, states[provider.id] == nil else { throw AgentReply.Code.badRequest }
        states[provider.id] = provider
        stateIDs = states.keys.sorted()
    }

    func start() { isRunning = true }
    func unregister(_ id: String) { actions[id] = nil; states[id] = nil; actionIDs = actions.keys.sorted(); stateIDs = states.keys.sorted() }

    func unregisterAll() {
        stop()
        actions.removeAll()
        states.removeAll()
        actionIDs = []
        stateIDs = []
    }

    func stop() {
        isRunning = false
        generation = UUID()
    }

    func handle(_ request: AgentRequest) async -> AgentReply {
        let reply: AgentReply
        do {
            try Task.checkCancellation()
            guard request.isValid else { throw AgentReply.Code.badRequest }
            guard isRunning else { throw AgentReply.Code.notRunning }
            let operation = generation
            let result = try await evaluate(request, operation: operation)
            try validate(operation)
            reply = .init(code: .ok, result: result)
        } catch let code as AgentReply.Code {
            reply = .init(code: code)
        } catch {
            reply = .init(code: .failed)
        }
        await didComplete(request, reply)
        return reply
    }

    private func evaluate(_ request: AgentRequest, operation: UUID) async throws -> AgentJSON {
        switch request.verb {
        case .status:
            return .object(["running": .bool(isRunning), "protocolVersion": .number(1)])
        case .list:
            return .object([
                "actions": .array(actionIDs.compactMap { actions[$0] }.map {
                    $0.action.json(available: $0.isAvailable())
                }),
                "states": .array(stateIDs.compactMap { states[$0] }.map {
                    .object(["id": .string($0.id), "title": .string($0.title), "available": .bool($0.isAvailable())])
                })
            ])
        case .get:
            guard let id = request.id, let provider = states[id] else { throw AgentReply.Code.badRequest }
            guard provider.isAvailable() else { throw AgentReply.Code.failed }
            let value = try await provider.read()
            try validate(operation)
            guard provider.isAvailable() else { throw AgentReply.Code.failed }
            return value
        case .audit:
            guard let readAudit else { throw AgentReply.Code.failed }
            return try await readAudit()
        case .run:
            return try await run(request, operation: operation)
        case .mcp: return try await receiveMCP?(request) ?? { throw AgentReply.Code.notRunning }()
        }
    }

    private func run(_ request: AgentRequest, operation: UUID) async throws -> AgentJSON {
        guard let id = request.id, let entry = actions[id], entry.action.parameters.accepts(request.parameters) else {
            throw AgentReply.Code.badRequest
        }
        guard entry.isAvailable() else { throw AgentReply.Code.failed }
        if request.dryRun { return entry.action.json(available: true) }
        let approved = await authorize(entry.action, request.parameters)
        try validate(operation)
        guard approved else { throw AgentReply.Code.declined }
        guard entry.isAvailable() else { throw AgentReply.Code.failed }
        return try await entry.run(request.parameters)
    }

    private func validate(_ operation: UUID) throws {
        try Task.checkCancellation()
        guard isRunning, generation == operation else { throw AgentReply.Code.notRunning }
    }
}
