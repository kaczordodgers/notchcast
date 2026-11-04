import SwiftUI

struct ColorPickerSettingsSection: View {
    @Bindable var module: ColorPickerModule
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Toggle(isOn: Binding(
            get: { preferences.isOn(.colorPicker) },
            set: { preferences.set(.colorPicker, $0) })) {
                SettingsRowTitle(.notchcastCaptureAndDictation, "Color Picker")
                Text(NotchcastFeature.colorPicker.subtitle)
            }
        Picker(selection: $module.format) {
            Text(verbatim: "#RRGGBB").tag(ColorPickerFormat.hex)
            Text(verbatim: "#rrggbb").tag(ColorPickerFormat.hexLowercase)
            Text(verbatim: "rgb()").tag(ColorPickerFormat.rgb)
            Text(verbatim: "hsl()").tag(ColorPickerFormat.hsl)
            Text(verbatim: "SwiftUI Color").tag(ColorPickerFormat.swiftUIColor)
            Text(verbatim: "NSColor #colorLiteral").tag(ColorPickerFormat.nsColorLiteral)
        } label: {
            SettingsRowTitle(.notchcastCaptureAndDictation, "Color format")
        }
        .settingsEnabled(preferences.isOn(.colorPicker))
    }
}
