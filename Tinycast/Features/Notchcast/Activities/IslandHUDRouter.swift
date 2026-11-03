import Foundation

@MainActor
enum IslandHUDRouter {
    static func show(_ text: String, tone: DialogTone) -> Bool {
        guard shouldRoute else { return false }
        let islandTone: IslandMessage.Tone = switch tone {
        case .neutral: .neutral
        case .success: .success
        case .danger: .danger
        }
        IslandActivityCenter.shared.showMessage(text, tone: islandTone, dwell: Theme.Duration.messageHUD)
        return true
    }

    static func showProgress(_ text: String, onCancel: (() -> Void)?) -> Bool {
        guard shouldRoute else { return false }
        IslandActivityCenter.shared.showProgress(text, onCancel: onCancel)
        return true
    }

    static func dismiss() -> Bool {
        let routed = shouldRoute
        IslandActivityCenter.shared.dismissMessage()
        return routed
    }

    private static var shouldRoute: Bool {
        shouldRoute(statusMessagesEnabled: NotchcastPreferences.shared.isOn(.islandStatusMessages))
    }

    static func shouldRoute(statusMessagesEnabled: Bool) -> Bool {
        IslandActivityCenter.shared.presenter != nil && statusMessagesEnabled
    }
}

@MainActor
fileprivate enum NotchcastPreferences {
    enum Feature { case islandStatusMessages }
    static let shared = Self.self
    static func isOn(_: Feature) -> Bool { true }
}
