import Foundation

@MainActor
enum IslandHUDRouter {
    private static var hudNotice: IslandActivityCenter.NoticeHandle?

    static func show(_ text: String, tone: DialogTone) -> Bool {
        guard shouldRoute else { dismiss(); return false }
        let islandTone: IslandMessage.Tone = switch tone {
        case .neutral: .neutral
        case .success: .success
        case .danger: .danger
        }
        hudNotice = IslandActivityCenter.shared.showMessage(text, tone: islandTone, dwell: Theme.Duration.messageHUD)
        return true
    }

    static func showProgress(_ text: String, onCancel: (() -> Void)?) -> Bool {
        guard let notice = progress(text, onCancel: onCancel) else { dismiss(); return false }
        hudNotice = notice
        return true
    }

    /// Ends the HUD's own notice only; one another poster put up stays.
    static func dismiss() {
        guard let hudNotice else { return }
        self.hudNotice = nil
        IslandActivityCenter.shared.dismiss(hudNotice)
    }

    /// A progress notice its caller owns; nil when no presenter would show it.
    static func progress(_ text: String, onCancel: (() -> Void)? = nil) -> IslandActivityCenter.NoticeHandle? {
        guard shouldRoute else { return nil }
        return IslandActivityCenter.shared.showProgress(text, onCancel: onCancel)
    }

    /// Every fork notice enters the centre here; nil when no presenter shows it now, though it still waits.
    @discardableResult
    static func post(_ text: String, tone: IslandMessage.Tone = .neutral, id: String? = nil,
                     symbol: String? = nil,
                     dwell: TimeInterval = Theme.Duration.messageHUD) -> IslandActivityCenter.NoticeHandle? {
        let notice = IslandActivityCenter.shared.showMessage(text, tone: tone, dwell: dwell, id: id, symbol: symbol)
        return shouldRoute ? notice : nil
    }

    private static var shouldRoute: Bool {
        IslandActivityCenter.shared.hasPresenter
            && NotchcastPreferences.shared.isOn(.islandStatusMessages)
    }
}
