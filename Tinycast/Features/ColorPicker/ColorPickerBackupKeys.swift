import Foundation

extension NotchcastFeature.BackupKeys {
    static let colorPicker = Self(allowed: [
        ColorPickerService.formatKey: .string(14, ["hex", "hexLowercase", "rgb", "hsl", "swiftUIColor", "nsColorLiteral"]),
    ], excluded: [], snapshot: {
        [ColorPickerService.formatKey: ColorPickerModule.shared.format.rawValue]
    }, apply: { values in
        if let value = values[ColorPickerService.formatKey] as? String, let format = ColorPickerFormat(rawValue: value) {
            ColorPickerModule.shared.format = format
        }
    })
}
