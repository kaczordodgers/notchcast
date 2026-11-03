import SwiftUI

struct SpotifySettingsSection: View {
    @Environment(SpotifySettingsCoordinator.self) private var coordinator
    @FocusState private var editingName: Bool
    @State private var deviceName = ""
    private let preferences = NotchcastPreferences.shared
    private var module: SpotifyConnectModule { coordinator.module }

    var body: some View {
        @Bindable var coordinator = coordinator
        Section {
            NotchcastFeatureToggle(feature: .spotifyConnect, anchor: .notchcastSpotify)
                .settingsEnabled(preferences.isOn(.musicNowPlaying))
            if preferences.isOn(.spotifyConnect) {
                SpotifyStatusRow(module: module)
                LabeledContent {
                    if coordinator.hasKey {
                        Button("Remove…", role: .destructive) { coordinator.removeKey() }
                    } else {
                        HStack(spacing: Theme.Spacing.md) {
                            RevealableSecureField(title: String(localized: "API key"), text: $coordinator.keyText,
                                                  prompt: Text("Paste API key"))
                                .labelsHidden()
                                .frame(width: NotchcastSettingsMetrics.keyField)
                            Button("Save") { coordinator.save() }.disabled(!coordinator.canSave)
                            Button("Import…") { coordinator.importKey() }
                        }
                    }
                } label: {
                    SettingsRowTitle(.notchcastSpotify, "API key")
                    if coordinator.hasKey {
                        // ai-design-check-ignore-next-line sentence-case -- Proper noun: Keychain.
                        Text("Stored in Keychain.")
                    } else {
                        Text(SpotifySettingsLinks.keyDescription)
                    }
                }
                LabeledContent {
                    TextField("Device name", text: $deviceName)
                        .labelsHidden()
                        .frame(width: NotchcastSettingsMetrics.deviceField)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .focused($editingName)
                        .onSubmit { applyDeviceName() }
                        .onChange(of: editingName) { _, editing in if !editing { applyDeviceName() } }
                        .accessibilityLabel("Device name")
                } label: {
                    SettingsRowTitle(.notchcastSpotify, "Device name")
                    Text("How this Mac appears in Spotify.")
                }
                SpotifyBuildRow(module: module, install: coordinator.installBuild)
            }
        } header: {
            SettingsSectionHeader(.notchcastSpotify)
        } footer: {
            if preferences.isOn(.spotifyConnect) { Text(SpotifySettingsLinks.termsDescription) }
        }
        .settingsEnabled(preferences.isOn(.island) && preferences.isOn(.musicNowPlaying))
        .onAppear {
            deviceName = module.deviceName
            if preferences.isEnabled(.spotifyConnect) { coordinator.refreshKey() }
        }
        .onChange(of: preferences.isEnabled(.spotifyConnect)) { _, enabled in
            if enabled { coordinator.refreshKey() }
        }
    }

    private func applyDeviceName() {
        module.setDeviceName(deviceName)
        deviceName = module.deviceName
    }
}
