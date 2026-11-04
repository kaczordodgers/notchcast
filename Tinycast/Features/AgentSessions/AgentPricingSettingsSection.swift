import SwiftUI

struct AgentPricingSettingsSection: View {
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { preferences.isOn(.agentPricing) },
                                 set: { preferences.set(.agentPricing, $0) })) {
                SettingsRowTitle(.notchcastSystem, verbatim: NotchcastFeature.agentPricing.title)
                Text(NotchcastFeature.agentPricing.subtitle)
            }
        }
        .settingsEnabled(preferences.isOn(.agentSessions))
    }
}
