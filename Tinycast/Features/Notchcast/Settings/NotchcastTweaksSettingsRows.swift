import SwiftUI

struct NotchcastTweaksSettingsRows: View {
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        ForEach(NotchcastFeature.systemToolsSettingsFeatures, id: \.self) { feature in
            Toggle(isOn: Binding(
                get: { preferences.isOn(feature) },
                set: { enabled in
                    guard SystemToolsHelperPolicy.available(feature) else { return }
                    Task { await NotchcastCore.systemTools.set(feature, enabled: enabled) }
                })) {
                SettingsRowTitle(.notchcastTweaks, verbatim: feature.title)
                if SystemToolsHelperPolicy.available(feature) {
                    Text(feature.subtitle)
                } else {
                    Text("Needs the Notchcast helper update")
                }
            }
            .settingsEnabled(SystemToolsHelperPolicy.available(feature))
            if feature == .startupItems, preferences.isOn(feature) {
                ForEach(NotchcastCore.systemTools.items, id: \.path) { item in
                    if item.disabled == nil || item.loaded == nil {
                        Text(verbatim: item.label)
                    } else {
                    Toggle(item.label, isOn: Binding(
                        get: { item.disabled == false },
                        set: { enabled in
                            Task { await NotchcastCore.systemTools.set(item, enabled: enabled) }
                        }))
                        .settingsEnabled(item.kind == .userAgent && !NotchcastCore.systemTools.busy)
                    }
                }
            }
        }
        .task { await NotchcastCore.systemTools.refresh() }
    }
}
