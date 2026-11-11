import Foundation

enum ClearNotificationsFailure: LocalizedError, Equatable, Sendable {
    case accessibilityRequired
    case automationRequired
    case notificationCenterUnavailable
    case unreadable
    case notificationsRemain
    case invalidResult
    case preparationFailed
    case automationFailed(Int)

    var errorDescription: String? {
        switch self {
        case .accessibilityRequired:
            String(localized: "Allow Accessibility access to clear notifications.", table: "Notchcast")
        case .automationRequired:
            String(localized: "Allow Automation access to clear notifications.", table: "Notchcast")
        case .notificationCenterUnavailable:
            String(localized: "Notification Center could not be opened.", table: "Notchcast")
        case .unreadable:
            String(localized: "Notification Center could not be read.", table: "Notchcast")
        case .notificationsRemain:
            String(localized: "Some notifications could not be cleared.", table: "Notchcast")
        case .invalidResult, .preparationFailed:
            String(localized: "Could not clear notifications.", table: "Notchcast")
        case .automationFailed(let code):
            String(localized: "Could not clear notifications (error \(code)).", table: "Notchcast")
        }
    }

    static func appleScript(code: Int) -> Self {
        switch code {
        case -25211: .accessibilityRequired
        case -1743: .automationRequired
        case -10001: .notificationCenterUnavailable
        case -10002, -1719, -1728: .unreadable
        case -10003: .notificationsRemain
        default: .automationFailed(code)
        }
    }
}
