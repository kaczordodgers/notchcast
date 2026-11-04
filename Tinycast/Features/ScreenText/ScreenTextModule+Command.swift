import Foundation

extension ScreenTextModule {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "screen-text", name: String(localized: "Capture Text"), sfSymbol: "text.viewfinder",
        isEnabled: { NotchcastPreferences.shared.isOn(.screenText) },
        run: { NotchcastCore.screenText.capture {
            AppCore.shared.showMessage($0, tone: .danger)
        } })
}
