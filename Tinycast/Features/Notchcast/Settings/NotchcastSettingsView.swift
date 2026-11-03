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
                }
            }
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
