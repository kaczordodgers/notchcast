import Foundation

extension SystemNoticesModule {
    static func postNotice(_ notice: SystemNoticeEngine.Notice) {
        let text: String
        let warning: Bool
        switch notice {
        case .wifi(let available):
            let status = available ? String(localized: "Connected") : String(localized: "Disconnected")
            text = String(localized: "Wi-Fi: \(status)")
            warning = !available
        case .tailscale(let state):
            let status = switch state {
            case .connected: String(localized: "Connected")
            case .disconnected: String(localized: "Disconnected")
            case .starting: String(localized: "Starting…")
            case .needsLogin: String(localized: "Sign In")
            case .needsApproval, .unavailable: String(localized: "Unavailable")
            }
            text = String(localized: "Tailscale: \(status)")
            warning = state != .connected
        case .lowBattery(let percent, _):
            text = String(localized: "Low battery: \(percent)%")
            warning = true
        }
        IslandActivityCenter.shared.showMessage(text, tone: warning ? .danger : .neutral, dwell: 5)
    }
}
