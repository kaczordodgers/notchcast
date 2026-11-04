import Foundation

enum DisplayBrightnessCommands {
    static let settings = NotchcastCommand(
        slug: "display-brightness", name: String(localized: "Display Brightness"), sfSymbol: "sun.max",
        isEnabled: { NotchcastPreferences.shared.isOn(.displayBrightness) },
        run: { AppCore.shared.settingsCoordinator.showSettings(tab: .notchcast) })
}
