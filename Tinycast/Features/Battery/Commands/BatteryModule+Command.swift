import Foundation

extension BatteryModule {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "keep-awake", name: String(localized: "Toggle Keep Awake"),
        sfSymbol: "cup.and.saucer", feature: .keepAwake,
        isEnabled: { NotchcastPreferences.shared.isOn(.keepAwake) },
        run: { NotchcastCore.battery.toggleKeepAwake() })
}
