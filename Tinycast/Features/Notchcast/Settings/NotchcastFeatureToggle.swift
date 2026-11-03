import SwiftUI

struct NotchcastFeatureToggle: View {
    let feature: NotchcastFeature
    let anchor: SettingsAnchor
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Toggle(isOn: Binding(get: { preferences.isOn(feature) }, set: { preferences.set(feature, $0) })) {
            SettingsRowTitle(anchor, verbatim: feature.title)
            Text(feature.subtitle)
        }
        .accessibilityLabel(feature.title)
        .accessibilityHint(feature.subtitle)
    }
}
