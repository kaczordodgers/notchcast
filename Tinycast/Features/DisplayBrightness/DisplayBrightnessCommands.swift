import Foundation

enum DisplayBrightnessCommands {
    static let settings = NotchcastCommand(
        slug: "display-brightness", name: String(localized: "Display Brightness"),
        sfSymbol: "sun.max", feature: .displayBrightness,
        isEnabled: { NotchcastPreferences.shared.isOn(.displayBrightness) },
        run: {
            AppCore.shared.settingsCoordinator.showSettings(
                tab: .notchcastWindowsAndDisplay, revealing: .section(.notchcastBrightness))
        })
}
