import AppKit

@MainActor
final class AgentThreadsModule: NotchcastModule {
    let state = AgentThreadsState()
    func start() { state.start() }
    func stop() { state.stop() }
    func setActive(_ active: Bool) { state.setActive(active) }

    nonisolated static let refreshCommand = NotchcastCommand(
        slug: "refresh-agent-threads", name: String(localized: "Refresh Agent Threads"),
        sfSymbol: "arrow.clockwise", feature: .agentThreads,
        isEnabled: { NotchcastPreferences.shared.isOn(.agentThreads) },
        run: { NotchcastCore.agentThreads.state.refresh { state in
            AppCore.shared.showMessage(state.refreshMessage, tone: .neutral)
        } })
    nonisolated static let waitingCommand = NotchcastCommand(
        slug: "open-waiting-agent-thread", name: String(localized: "Open Waiting Agent Thread"),
        sfSymbol: "bubble.left", feature: .agentThreads,
        isEnabled: { NotchcastPreferences.shared.isOn(.agentThreads) },
        run: { NotchcastCore.agentThreads.openWaiting() })

    private func openWaiting() {
        state.refresh { state in
            if let message = state.waitingMessage {
                AppCore.shared.showMessage(message, tone: .neutral)
            } else if let thread = state.threads.first(where: { $0.phase.waiting }) {
                NSWorkspace.shared.open(thread.link)
            }
        }
    }
}
