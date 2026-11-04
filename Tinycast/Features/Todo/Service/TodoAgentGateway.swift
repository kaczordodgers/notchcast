import Foundation

@MainActor
final class TodoAgentGateway {
    enum Failure: Error, Equatable {
        case denied
        case declined
        case invalidAgent
        case cancelled
        case request(TodoAgentError)
        case store
    }

    struct Audit: Equatable, Sendable {
        let agent: String
        let action: String
        let taskIDs: [String]
        let result: FailureCode
    }

    enum FailureCode: String, Sendable {
        case succeeded, denied, declined, invalidAgent, cancelled, request, store
    }

    private let store: TodoStore
    private let grants: AgentGrantStore
    private let clock: () -> Date
    private let confirm: (AgentConfirmationEngine.Pending) -> AgentConfirmationEngine.Choice
    private let audit: (Audit) -> Void
    private let requiresConfirmation: (TodoAgentRequest) -> Bool

    init(store: TodoStore, grants: AgentGrantStore, clock: @escaping () -> Date,
         requiresConfirmation: @escaping (TodoAgentRequest) -> Bool,
         confirm: @escaping (AgentConfirmationEngine.Pending) -> AgentConfirmationEngine.Choice,
         audit: @escaping (Audit) -> Void) {
        self.store = store
        self.grants = grants
        self.clock = clock
        self.requiresConfirmation = requiresConfirmation
        self.confirm = confirm
        self.audit = audit
    }

    static func actionID(for request: TodoAgentRequest) -> String {
        switch request {
        case .list: "todo.read"
        case .claim: "todo.write.claim"
        case .comment: "todo.write.comment"
        case .move: "todo.write.move"
        case .complete: "todo.write.complete"
        case .release: "todo.write.release"
        case .releaseExpired: "todo.write.releaseExpired"
        }
    }

    func request(_ request: TodoAgentRequest, agent: String, calendar: Calendar,
                 staleAfterMinutes: Int, makeID: () -> String) throws(Failure) -> TodoAgentResponse {
        let action = Self.actionID(for: request)
        var ids = taskIDs(request)
        var result = FailureCode.denied
        defer { audit(Audit(agent: agent, action: action, taskIDs: ids, result: result)) }
        do {
            guard !agent.isEmpty, agent == agent.trimmingCharacters(in: .whitespacesAndNewlines),
                  agent.utf8.count <= 256, !agent.contains(where: { $0.isNewline || $0.asciiValue == 0 }),
                  matchesAgent(request, agent: agent) else { throw Failure.invalidAgent }
            guard AgentConsentPolicy.decide(agentID: agent, actionID: action, danger: .consent,
                grants: grants.grants, now: clock()) == .allow
            else { throw Failure.denied }
            if case .list = request {} else if requiresConfirmation(request) {
                try confirmation(agent: agent, action: action)
            }
            try Task.checkCancellation()
            guard grants.grants.contains(where: { $0.covers(agentID: agent, actionID: action, now: clock()) })
            else { throw Failure.denied }
            let before = store.state
            let plan = try TodoAgentAPI.plan(request, state: before, now: clock(), calendar: calendar,
                                            staleAfterMinutes: staleAfterMinutes, makeID: makeID)
            if case .list = request {
                // Planning also sweeps expired claims; a read grant must never commit that sweep.
            } else if case .batch(let commands) = plan.command, !commands.isEmpty {
                do { try store.perform(plan.command) } catch { throw Failure.store }
            }
            switch plan.response {
            case .tasks(let tasks): ids = tasks.map(\.id).sorted()
            case .task(let task): ids = [task.id]
            case .released(let released): ids = released
            }
            ids = Set(ids + before.tasks.keys.filter { before.tasks[$0] != store.state.tasks[$0] }).sorted()
            result = .succeeded
            return plan.response
        } catch {
            let failure: Failure
            switch error {
            case let value as Failure: failure = value
            case let value as TodoAgentError: failure = .request(value)
            case is CancellationError: failure = .cancelled
            default: failure = .store
            }
            switch failure {
            case .denied: result = .denied
            case .declined: result = .declined
            case .invalidAgent: result = .invalidAgent
            case .cancelled: result = .cancelled
            case .request: result = .request
            case .store: result = .store
            }
            throw failure
        }
    }

    private func confirmation(agent: String, action: String) throws(Failure) {
        var engine = AgentConfirmationEngine()
        let now = clock()
        let request = AgentConfirmationEngine.Request(id: UUID(), agentID: agent, client: "todo",
            actionID: action, parameters: [:], deadline: now.addingTimeInterval(60))
        let replies = engine.receive(request, danger: .dangerous, enabled: true, now: now)
        guard replies.isEmpty, let pending = engine.current else { throw .declined }
        let choice = confirm(pending)
        let decisions = engine.decide(id: request.id, choice: choice, enabled: true, now: clock())
        guard decisions.contains(where: { $0.id == request.id && $0.verdict == .allowOnce }) else {
            throw .declined
        }
    }

    private func taskIDs(_ request: TodoAgentRequest) -> [String] {
        switch request {
        case .claim(let id, _), .comment(let id, _, _), .move(let id, _, _),
             .complete(let id, _), .release(let id, _): [id]
        case .list, .releaseExpired: []
        }
    }

    private func matchesAgent(_ request: TodoAgentRequest, agent: String) -> Bool {
        switch request {
        case .claim(_, let name), .comment(_, let name, _), .move(_, let name, _),
             .complete(_, let name), .release(_, let name): name == agent
        case .list, .releaseExpired: true
        }
    }
}
