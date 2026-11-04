import SwiftUI

struct IslandHoverDelaySettingRow: View {
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Picker(selection: Binding(
            get: { preferences.islandHoverDelay },
            set: { preferences.islandHoverDelay = $0 })) {
            ForEach(NotchcastPreferences.HoverDelay.allCases) { delay in
                Text(delay.title).tag(delay)
            }
        } label: {
            Text("Hover delay")
        }
        .settingsEnabled(preferences.isOn(.island))
    }
}
