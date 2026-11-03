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

    static func dismiss() {
        IslandActivityCenter.shared.dismissMessage()
    }

    private static var shouldRoute: Bool {
        IslandActivityCenter.shared.presenter != nil
            && NotchcastPreferences.shared.isOn(.islandStatusMessages)
    }
}
