import Foundation

extension ScreenTextModule {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "screen-text", name: String(localized: "Capture Text", table: "Notchcast"), sfSymbol: "text.viewfinder", feature: .screenText,
        isEnabled: { NotchcastPreferences.shared.isOn(.screenText) },
        run: { ScreenTextModule.shared.capture {
            NotchcastHost.current.showMessage($0, .danger)
        } })
}
