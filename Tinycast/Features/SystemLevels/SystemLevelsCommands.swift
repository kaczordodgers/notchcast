import Foundation

enum SystemLevelsCommands {
    static let presets: [NotchcastCommand] = [
        command(0, "Set Volume to 0%"), command(25, "Set Volume to 25%"),
        command(50, "Set Volume to 50%"), command(75, "Set Volume to 75%"),
        command(100, "Set Volume to 100%"),
    ]

    private static func command(_ percent: Int, _ name: String.LocalizationValue) -> NotchcastCommand {
        NotchcastCommand(
            slug: "volume-\(percent)", name: String(localized: name), sfSymbol: "speaker.wave.2", feature: .volumeLevels,
            isEnabled: { NotchcastPreferences.shared.isOn(.island) && NotchcastPreferences.shared.isOn(.volumeLevels) },
            run: {
                let service = SystemLevelsModule.shared.service
                Task { @MainActor in
                    guard service.isRunning, NotchcastPreferences.shared.isOn(.island),
                          NotchcastPreferences.shared.isOn(.volumeLevels) else { return }
                    let result = await service.apply(.setVolume(Double(percent) / 100))
                    guard !Task.isCancelled, service.isRunning else { return }
                    if case .fallbackToNativeKeys = result {
                        let message = String(localized: "The current audio output does not support software volume.")
                        NotchcastHost.current.showMessage(message, .success)
                    }
                }
            })
    }
}
