import SwiftUI

struct NotchcastSettingsView: View {
    @Environment(SettingsNavigationState.self) private var navigation
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Form {
            Section("Island") {
                ForEach(NotchcastFeature.allCases, id: \.self) { feature in
                    SettingsRow(title: feature.title, subtitle: feature.subtitle) {
                        Toggle(feature.title, isOn: Binding(
                            get: { preferences.isOn(feature) },
                            set: { preferences.set(feature, $0) }))
                            .labelsHidden()
                            .accessibilityLabel(feature.title)
                    }
                    if feature == .islandHoverOpen {
                        Picker(selection: Binding(
                            get: { preferences.islandHoverDelay },
                            set: { preferences.islandHoverDelay = $0 })) {
                            ForEach(NotchcastPreferences.HoverDelay.allCases) { delay in
                                Text(delay.title).tag(delay)
                            }
                        } label: {
                            SettingsRowTitle(.notchcastHover, "Hover delay")
                        }
                        .settingsEnabled(preferences.isOn(.island) && preferences.isOn(.islandHoverOpen))
                    }
                }
            }
            .settingsAnchor(.notchcastHover)
            FeatureCommandsSection(owner: .notchcast, anchor: .notchcastShortcuts)
                .settingsEnabled(preferences.isOn(.island))
            if preferences.isOn(.island) && preferences.isOn(.islandHoverOpen) {
                Section("Permissions") {
                    SettingsRow(
                        title: String(localized: "Accessibility"),
                        subtitle: String(localized: "Required to open the island on hover.")
                    ) {
                        Button("Permissions") { navigation.select(.permissions) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.notchcast)
    }
}
