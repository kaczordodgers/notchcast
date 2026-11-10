import Foundation

extension ColorPickerModule {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "pick-color", name: String(localized: "Pick Color", table: "Notchcast"), sfSymbol: "eyedropper", feature: .colorPicker,
        isEnabled: { NotchcastPreferences.shared.isOn(.colorPicker) },
        run: {
            ColorPickerModule.shared.pick { outcome in
                if outcome == .copyFailed { NotchcastHost.current.showMessage(String(localized: "Pick Color", table: "Notchcast"), .danger) }
            }
        })
}
