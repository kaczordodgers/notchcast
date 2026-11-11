import Foundation

extension AgentSessionsModule {
    nonisolated static let refreshCommand = NotchcastCommand(
        slug: "refresh-agent-session-logs", name: String(localized: "Refresh Agent Session Logs", table: "Notchcast"),
        sfSymbol: "arrow.clockwise", feature: .agentSessions, isEnabled: { NotchcastPreferences.shared.isOn(.agentSessions) },
        run: { AgentSessionsModule.shared.refresh() })
}
