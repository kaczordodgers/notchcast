import SwiftUI

struct PasteToolsSettingsSection: View {
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Section {
            ForEach([NotchcastFeature.pastePlain, .pasteImage], id: \.self) { feature in
                Toggle(isOn: Binding(
                    get: { preferences.isOn(feature) },
                    set: { preferences.set(feature, $0) })) {
                    SettingsRowTitle(.notchcastPaste, verbatim: feature.title)
                }
            }
        } header: {
            SettingsSectionHeader(.notchcastPaste)
        }
    }
}
