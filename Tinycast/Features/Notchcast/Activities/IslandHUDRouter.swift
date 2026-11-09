import Foundation

@MainActor
enum IslandHUDRouter {
    private static var hudNotice: IslandActivityCenter.NoticeHandle?

    static func show(_ text: String, tone: DialogTone) -> Bool {
        let islandTone: IslandMessage.Tone = switch tone {
        case .neutral: .neutral
        case .success: .success
        case .danger: .danger
        }
        guard let notice = post(text, tone: islandTone) else { dismiss(); return false }
        hudNotice = notice
        return true
    }

    static func showProgress(_ text: String, onCancel: (() -> Void)?) -> Bool {
        guard shouldRoute else { dismiss(); return false }
        hudNotice = IslandActivityCenter.shared.showProgress(text, onCancel: onCancel)
        return true
    }

    /// Ends the HUD's own notice only; one another poster put up stays.
    static func dismiss() {
        guard let hudNotice else { return }
        self.hudNotice = nil
        IslandActivityCenter.shared.dismiss(hudNotice)
    }

    /// The one gate for an island notice: nil when the island would not show it.
    @discardableResult
    static func post(_ text: String, tone: IslandMessage.Tone = .neutral) -> IslandActivityCenter.NoticeHandle? {
        guard shouldRoute else { return nil }
        return IslandActivityCenter.shared.showMessage(text, tone: tone, dwell: Theme.Duration.messageHUD)
    }

    private static var shouldRoute: Bool {
        IslandActivityCenter.shared.hasPresenter
            && NotchcastPreferences.shared.isOn(.islandStatusMessages)
    }
}
