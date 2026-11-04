import Foundation

@MainActor
protocol AgentConfirmationTransport: AnyObject {
    func reply(_ reply: AgentConfirmationEngine.Reply)
}

@MainActor
protocol AgentConfirmationActions: AnyObject {
    func confirmationDanger(agentID: String, actionID: String) -> AgentConsentPolicy.Danger?
}
