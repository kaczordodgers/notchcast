import Foundation
import Observation

@MainActor
@Observable
final class AgentConfirmationCoordinator {
    private(set) var engine = AgentConfirmationEngine()
    private let transport: any AgentConfirmationTransport
    private let actions: any AgentConfirmationActions
    private let grants: AgentGrantStore
    private let isEnabled: () -> Bool

    init(transport: any AgentConfirmationTransport, actions: any AgentConfirmationActions,
         grants: AgentGrantStore, isEnabled: @escaping () -> Bool) {
        self.transport = transport
        self.actions = actions
        self.grants = grants
        self.isEnabled = isEnabled
    }

    func receive(_ request: AgentConfirmationEngine.Request, now: Date) {
        send(engine.receive(request, danger: actions.confirmationDanger(
            agentID: request.agentID, actionID: request.actionID), enabled: isEnabled(), now: now))
    }

    func choose(id: UUID, choice: AgentConfirmationEngine.Choice, now: Date) throws {
        let pending = engine.current
        let replies = engine.decide(id: id, choice: choice, enabled: isEnabled(), now: now)
        for reply in replies {
            if reply.verdict == .alwaysAllow, let pending, pending.request.id == reply.id {
                do {
                    try grants.allow(agentID: pending.request.agentID, actionID: pending.request.actionID,
                                     danger: pending.danger)
                } catch {
                    transport.reply(.init(id: reply.id, verdict: .deny))
                    throw error
                }
            }
            transport.reply(reply)
        }
    }

    func tick(now: Date) { send(isEnabled() ? engine.expire(now: now) : engine.denyAll()) }
    func stop() { send(engine.denyAll()) }

    private func send(_ replies: [AgentConfirmationEngine.Reply]) {
        for reply in replies { transport.reply(reply) }
    }
}
