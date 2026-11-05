import Foundation

extension OpenBotAgentsModule: NotchcastModule {
    nonisolated static let refreshCommand = NotchcastCommand(
        slug: "refresh-openbot-agents", name: String(localized: "Refresh OpenBot Agents", table: "Notchcast"),
        sfSymbol: "arrow.clockwise", feature: .openBotAgents, isEnabled: { NotchcastPreferences.shared.isOn(.openBotAgents) },
        run: { NotchcastCore.openBotAgents.refresh(reportResult: true) })

    static func report(count: Int?, failure: OpenBotFailure?) {
        let text: String
        if let count {
            text = String(localized: "OpenBot agents waiting: \(count)", table: "Notchcast")
        } else {
            switch failure {
            case .off: text = String(localized: "OpenBot off or Local scripts off.", table: "Notchcast")
            case .invalidURL: text = String(localized: "OpenBot requires a loopback URL.", table: "Notchcast")
            case .unauthorized: text = String(localized: "OpenBot authentication failed.", table: "Notchcast")
            case .forbidden: text = String(localized: "OpenBot access refused.", table: "Notchcast")
            case .missing: text = String(localized: "OpenBot item not found.", table: "Notchcast")
            case .rateLimited: text = String(localized: "OpenBot rate limit reached.", table: "Notchcast")
            case .server: text = String(localized: "OpenBot server failed.", table: "Notchcast")
            case .malformed: text = String(localized: "OpenBot returned invalid JSON.", table: "Notchcast")
            default: text = String(localized: "OpenBot is unreachable.", table: "Notchcast")
            }
        }
        AppCore.shared.showMessage(text, tone: .neutral)
    }
}
