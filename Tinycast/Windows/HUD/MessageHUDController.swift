import AppKit
import SwiftUI

@MainActor
final class MessageHUDController {
    private let presenter: HUDPresenter
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        presenter = HUDPresenter(
            anchor: .edgeInset(Theme.Size.hudEdgeOffset),
            dwell: Theme.Duration.messageHUD,
            screen: { settings.openOnCursorScreen ? .underCursor : .primary })
    }

    func show(message: String, tone: DialogTone = .success) {
        if IslandHUDRouter.show(message, tone: tone) { presenter.dismiss(); return }
        presenter.show(
            MessageHUDView(message: message, accessory: .tone(tone)).environment(\.metrics, metrics))
    }

    /// Stays up until the work it reports ends and something replaces it, or `dismiss()` runs.
    func showProgress(message: String, onCancel: (() -> Void)? = nil) {
        if IslandHUDRouter.showProgress(message, onCancel: onCancel) { presenter.dismiss(); return }
        presenter.show(
            MessageHUDView(message: message, accessory: .progress, onCancel: onCancel)
                .environment(\.metrics, metrics),
            dwells: false,
            interactive: onCancel != nil)
    }

    func dismiss() {
        IslandHUDRouter.dismiss()
        presenter.dismiss()
    }

    private var metrics: InterfaceMetrics { settings.interfaceSize.metrics }
}
