import AppKit

@MainActor
final class AgentThreadsModule: NotchcastModule {
    let state: AgentThreadsState
    private let availabilityChanged: () -> Void

    init(state: AgentThreadsState = AgentThreadsState(), availabilityChanged: @escaping () -> Void = {}) {
        self.state = state
        self.availabilityChanged = availabilityChanged
    }

    func start() { state.start(); availabilityChanged() }
    func stop() { state.stop(); availabilityChanged() }
    func setActive(_ active: Bool) { state.setActive(active) }

    nonisolated static let refreshCommand = NotchcastCommand(
        slug: "refresh-agent-threads", name: String(localized: "Refresh Agent Threads", table: "Notchcast"),
        sfSymbol: "arrow.clockwise", feature: .agentThreads,
        isEnabled: { NotchcastPreferences.shared.isOn(.agentThreads) },
        run: { NotchcastCore.agentThreads.state.refresh { state in
            NotchcastHost.current.showMessage(state.refreshMessage, .neutral)
        } })
    nonisolated static let waitingCommand = NotchcastCommand(
        slug: "open-waiting-agent-thread", name: String(localized: "Open Waiting Agent Thread", table: "Notchcast"),
        sfSymbol: "bubble.left", feature: .agentThreads,
        isEnabled: { NotchcastPreferences.shared.isOn(.agentThreads) },
        run: { NotchcastCore.agentThreads.openWaiting() })

    private func openWaiting() {
        state.refresh { state in
            if let message = state.waitingMessage {
                NotchcastHost.current.showMessage(message, .neutral)
            } else if let thread = state.threads.first(where: { $0.phase.waiting }) {
                NSWorkspace.shared.open(thread.link)
            }
        }
    }
}
