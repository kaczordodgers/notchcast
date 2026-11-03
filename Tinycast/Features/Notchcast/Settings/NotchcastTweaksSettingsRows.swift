import SwiftUI

struct NotchcastTweaksSettingsRows: View {
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        ForEach(NotchcastFeature.allCases.filter(\.isSystemTweak), id: \.self) { feature in
            Toggle(isOn: Binding(
                get: { preferences.isOn(feature) },
                set: { enabled in
                    guard SystemToolsHelperPolicy.available(feature) else { return }
                    preferences.set(feature, enabled)
                })) {
                SettingsRowTitle(.notchcastTweaks, verbatim: feature.title)
                if SystemToolsHelperPolicy.available(feature) {
                    Text(feature.subtitle)
                } else {
                    Text("Needs the Notchcast helper update")
                }
            }
            .settingsEnabled(SystemToolsHelperPolicy.available(feature))
        }
    }
}
