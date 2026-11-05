import Foundation

extension SystemNoticesModule {
    static func postNotice(_ notice: SystemNoticeEngine.Notice) {
        let text: String
        let warning: Bool
        switch notice {
        case .wifi(let available):
            let status = available ? String(localized: "Connected", table: "Notchcast") : String(localized: "Disconnected", table: "Notchcast")
            text = String(localized: "Wi-Fi: \(status)", table: "Notchcast")
            warning = !available
        case .tailscale(let state):
            let status = switch state {
            case .connected: String(localized: "Connected", table: "Notchcast")
            case .disconnected: String(localized: "Disconnected", table: "Notchcast")
            case .starting: String(localized: "Starting…")
            case .needsLogin: String(localized: "Sign In")
            case .needsApproval, .unavailable: String(localized: "Unavailable")
            }
            text = String(localized: "Tailscale: \(status)", table: "Notchcast")
            warning = state != .connected
        case .lowBattery(let percent, _):
            text = String(localized: "Low battery: \(percent)%", table: "Notchcast")
            warning = true
        }
        IslandActivityCenter.shared.showMessage(text, tone: warning ? .danger : .neutral, dwell: 5)
    }
}
