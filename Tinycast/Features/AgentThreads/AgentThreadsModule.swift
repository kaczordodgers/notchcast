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
        run: { NotchcastCore.agentThreads.state.refresh() })
    nonisolated static let waitingCommand = NotchcastCommand(
        slug: "open-waiting-agent-thread", name: String(localized: "Open Waiting Agent Thread"),
        sfSymbol: "bubble.left", feature: .agentThreads,
        isEnabled: { NotchcastPreferences.shared.isOn(.agentThreads) },
        run: { NotchcastCore.agentThreads.openWaiting() })

    private func openWaiting() {
        guard let thread = state.threads.first(where: { $0.phase.waiting }) else {
            AppCore.shared.showMessage(String(localized: "No waiting agent threads."), tone: .neutral)
            return
        }
        NSWorkspace.shared.open(thread.link)
    }
}
