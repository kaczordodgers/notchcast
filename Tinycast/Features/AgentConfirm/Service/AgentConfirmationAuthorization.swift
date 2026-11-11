import Foundation

@MainActor
final class AgentConfirmationAuthorization {
    typealias Dialog = @MainActor (AgentAction, String, [AgentConfirmationEngine.Choice]) async -> Int

    private final class Transport: AgentConfirmationTransport, AgentConfirmationActions {
        var continuations: [UUID: CheckedContinuation<Bool, Never>] = [:]
        var dangers: [String: AgentConsentPolicy.Danger] = [:]
        var approvals: Set<UUID> = []

        func reply(_ reply: AgentConfirmationEngine.Reply) {
            if reply.verdict != .deny, continuations[reply.id] != nil { approvals.insert(reply.id) }
            continuations.removeValue(forKey: reply.id)?.resume(returning: reply.verdict != .deny)
        }

        func confirmationDanger(agentID: String, actionID: String) -> AgentConsentPolicy.Danger? {
            dangers[actionID]
        }
    }

    private let transport = Transport()
    private let coordinator: AgentConfirmationCoordinator
    private let grants: AgentGrantStore
    private let isEnabled: () -> Bool
    private let dialog: Dialog
    private let timeout: Duration
    private var presenting = false
    private var shown: (id: UUID, task: Task<Void, Never>)?
    private var actions: [UUID: AgentAction] = [:]
    private var messages: [UUID: String] = [:]
    private var timers: [UUID: Task<Void, Never>] = [:]

    init(grants: AgentGrantStore, isEnabled: @escaping () -> Bool,
         timeout: Duration = AgentRequestTiming.confirmationTimeout, dialog: @escaping Dialog) {
        self.grants = grants
        self.isEnabled = isEnabled
        self.timeout = timeout
        self.dialog = dialog
        coordinator = AgentConfirmationCoordinator(transport: transport, actions: transport,
                                                  grants: grants, isEnabled: isEnabled)
    }

    func authorize(_ action: AgentAction, parameters: AgentJSON) async -> (@MainActor () -> Void)? {
        let danger: AgentConsentPolicy.Danger = switch action.danger {
        case .harmless: .harmless
        case .consent: .consent
        case .dangerous: .dangerous
        }
        if AgentConsentPolicy.decide(agentID: "local-cli", actionID: action.id,
            danger: danger, grants: action.parameters.properties.isEmpty ? grants.grants : [],
            now: Date()) == .allow { return {} }
        guard isEnabled(), !Task.isCancelled else { return nil }
        let id = UUID()
        transport.dangers[action.id] = danger
        actions[id] = action
        messages[id] = action.confirmationMessage(parameters: parameters)
        let seconds = timeout / .seconds(1)
        let request = AgentConfirmationEngine.Request(id: id, agentID: "local-cli", client: "local-cli",
            actionID: action.id, parameters: [:], deadline: Date().addingTimeInterval(seconds))
        let approved = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                transport.continuations[id] = continuation
                coordinator.receive(request, now: Date())
                timers[id] = Task { [weak self, timeout] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    self?.coordinator.tick(now: Date())
                }
                presentNext()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(id) }
        }
        actions.removeValue(forKey: id)
        messages.removeValue(forKey: id)
        timers.removeValue(forKey: id)?.cancel()
        if shown?.id == id { shown?.task.cancel() }
        guard approved else { return nil }
        return { [self] in
            presenting = false
            presentNext()
        }
    }

    func stop() {
        coordinator.stop()
        for timer in timers.values { timer.cancel() }
        timers.removeAll()
        shown?.task.cancel()
        actions.removeAll()
        messages.removeAll()
    }

    private func cancel(_ id: UUID) {
        transport.reply(.init(id: id, verdict: .deny))
    }

    private func presentNext() {
        guard !presenting else { return }
        coordinator.tick(now: Date())
        guard let pending = coordinator.engine.current else { return }
        let id = pending.request.id
        guard let action = actions[id] else {
            try? coordinator.choose(id: id, choice: .deny, now: Date())
            presentNext()
            return
        }
        presenting = true
        let message = messages[id] ?? ""
        let choices: [AgentConfirmationEngine.Choice] = pending.danger == .consent && action.parameters.properties.isEmpty
            ? [.allowOnce, .alwaysAllow, .deny] : [.allowOnce, .deny]
        shown = (id, Task {
            let index = await dialog(action, message, choices)
            shown = nil
            let choice = transport.continuations[id] != nil && choices.indices.contains(index) ? choices[index] : .deny
            try? coordinator.choose(id: id, choice: choice, now: Date())
            let approved = transport.approvals.remove(id) != nil
            if !approved {
                presenting = false
                presentNext()
            }
        })
    }
}
