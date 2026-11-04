import SwiftUI

struct MachRemoteSettingsSection: View {
    @Bindable private var preferences = NotchcastPreferences.shared

    var body: some View {
        Section {
            TextField("Remote Mac address", text: $preferences.remoteMacAddress)
            TextField("Remote terminal directory", text: $preferences.remoteTerminalDirectory)
            TextField("Remote update script path", text: $preferences.remoteUpdatePath)
        } header: {
            SettingsSectionHeader(.notchcastRemoteMac)
        }
        .settingsAnchor(.notchcastRemoteMac)
        .settingsEnabled(preferences.isOn(.machRemote))
    }
}
