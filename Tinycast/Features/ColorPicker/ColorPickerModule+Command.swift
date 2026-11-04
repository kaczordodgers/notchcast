import Foundation

extension ColorPickerModule {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "pick-color", name: String(localized: "Pick Color"), sfSymbol: "eyedropper", feature: .colorPicker,
        isEnabled: { NotchcastPreferences.shared.isOn(.colorPicker) },
        run: {
            NotchcastCore.colorPicker.pick { outcome in
                if outcome == .copyFailed { AppCore.shared.showMessage(String(localized: "Pick Color"), tone: .danger) }
            }
        })
}
