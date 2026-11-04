import Foundation
import OSLog

@MainActor
final class AgentConfirmationPresenter: AgentConfirmationTransport, AgentConfirmationActions {
    private let danger: AgentConsentPolicy.Danger
    private var verdict = AgentConfirmationEngine.Verdict.deny

    init(danger: AgentConsentPolicy.Danger) { self.danger = danger }

    func confirmationDanger(agentID: String, actionID: String) -> AgentConsentPolicy.Danger? { danger }
    func reply(_ reply: AgentConfirmationEngine.Reply) { verdict = reply.verdict }

    func ask(action: AgentAction, grants: AgentGrantStore, core: AppCore,
             isEnabled: @escaping () -> Bool) async -> Bool {
        let coordinator = AgentConfirmationCoordinator(transport: self, actions: self,
                                                       grants: grants, isEnabled: isEnabled)
        let id = UUID()
        coordinator.receive(.init(id: id, agentID: "local-cli", client: "local-cli",
                                  actionID: action.id, parameters: [:],
                                  deadline: Date().addingTimeInterval(120)), now: Date())
        guard coordinator.engine.current != nil else { return false }
        let choice: AgentConfirmationEngine.Choice
        if danger == .dangerous {
            choice = await core.confirm(title: action.title, message: "local-cli: " + action.id, symbol: nil,
                                        confirmTitle: String(localized: "Continue")) ? .allowOnce : .deny
        } else {
            let selection = await core.choose(title: action.title, message: "local-cli: " + action.id, symbol: nil,
                options: [.init(title: String(localized: "Continue")),
                          .init(title: String(localized: "Always Allow")),
                          .init(title: String(localized: "Cancel"), role: .cancel)], defaultIndex: 2)
            choice = selection == 0 ? .allowOnce : selection == 1 ? .alwaysAllow : .deny
        }
        guard !Task.isCancelled else { coordinator.stop(); return false }
        do {
            try coordinator.choose(id: id, choice: choice, now: Date())
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.notchcast.dev", category: "AgentBridge")
                .error("Unable to store agent grant: \(error)")
            return false
        }
        return verdict != .deny
    }
}
