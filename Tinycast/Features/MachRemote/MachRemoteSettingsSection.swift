import SwiftUI

struct MachRemoteSettingsSection: View {
    @Bindable private var preferences = NotchcastPreferences.shared

    var body: some View {
        Section {
            TextField("Remote Mac address", text: $preferences.remoteMacAddress)
        } header: {
            SettingsSectionHeader(.notchcastRemoteMac)
        }
        .settingsAnchor(.notchcastRemoteMac)
        .settingsEnabled(preferences.isOn(.machRemote))
    }
}

extension SettingsAnchor {
    static let notchcastRemoteMac = Self(tab: .notchcast, title: LocalizedStringResource("Remote Mac"))
}
