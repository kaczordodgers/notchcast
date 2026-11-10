import Foundation

enum ClearNotificationsFailure: Error, Equatable, Sendable {
    case accessibilityRequired
    case automationRequired
    case notificationCenterUnavailable
    case unreadable
    case notificationsRemain
    case invalidResult
    case preparationFailed
    case automationFailed(Int)

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
