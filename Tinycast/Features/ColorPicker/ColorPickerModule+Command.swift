import Foundation

extension ColorPickerModule {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "pick-color", name: String(localized: "Pick Color"), sfSymbol: "eyedropper",
        isEnabled: { NotchcastPreferences.shared.isOn(.colorPicker) },
        run: {
            NotchcastCore.colorPicker.pick { copied in
                if !copied {
                    AppCore.shared.showMessage(String(localized: "Could not copy to clipboard."), tone: .danger)
                }
            }
        })
}
