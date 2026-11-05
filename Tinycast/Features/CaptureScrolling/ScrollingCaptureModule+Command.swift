import Foundation

extension ScrollingCaptureModule {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "scrolling-capture", name: String(localized: "Scrolling Capture", table: "Notchcast"),
        sfSymbol: "rectangle.expand.vertical", feature: .scrollingCapture,
        isEnabled: { NotchcastPreferences.shared.isOn(.scrollingCapture) },
        run: { NotchcastCore.scrollingCapture.capture {
            AppCore.shared.showMessage($0, tone: $1 == .danger ? .danger : .neutral)
        } })
}
