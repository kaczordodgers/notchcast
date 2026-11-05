import Foundation

extension OpenBotAgentsModule: NotchcastModule {
    nonisolated static let refreshCommand = NotchcastCommand(
        slug: "refresh-openbot-agents", name: String(localized: "Refresh OpenBot Agents"),
        sfSymbol: "arrow.clockwise", feature: .openBotAgents, isEnabled: { NotchcastPreferences.shared.isOn(.openBotAgents) },
        run: { NotchcastCore.openBotAgents.refresh(reportResult: true) })

    static func report(count: Int?, failure: OpenBotFailure?) {
        let text: String
        if let count {
            text = String(localized: "OpenBot agents waiting: \(count)")
        } else {
            switch failure {
            case .off: text = String(localized: "OpenBot off or Local scripts off.")
            case .invalidURL: text = String(localized: "OpenBot requires a loopback URL.")
            case .unauthorized: text = String(localized: "OpenBot authentication failed.")
            case .forbidden: text = String(localized: "OpenBot access refused.")
            case .missing: text = String(localized: "OpenBot item not found.")
            case .rateLimited: text = String(localized: "OpenBot rate limit reached.")
            case .server: text = String(localized: "OpenBot server failed.")
            case .malformed: text = String(localized: "OpenBot returned invalid JSON.")
            default: text = String(localized: "OpenBot is unreachable.")
            }
        }
        AppCore.shared.showMessage(text, tone: .neutral)
    }
}
