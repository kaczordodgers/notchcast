import SwiftUI

struct SpotifyStatusSettingRow: View {
    @Environment(SpotifySettingsCoordinator.self) private var coordinator

    var body: some View {
        Group {
            SpotifyStatusRow(module: coordinator.module)
        }
        .settingsEnabled(NotchcastPreferences.shared.isOn(.island)
            && NotchcastPreferences.shared.isOn(.musicNowPlaying))
    }
}

struct SpotifyAPIKeySettingRow: View {
    @Environment(SpotifySettingsCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var coordinator = coordinator
        Group {
            LabeledContent {
                if coordinator.hasKey {
                    Button(String(localized: "Remove…", table: "Notchcast"), role: .destructive) { coordinator.removeKey() }
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
                    Text("Stored in Keychain.", tableName: "Notchcast")
                } else {
                    Text(SpotifySettingsLinks.keyDescription)
                }
            }
            .onAppear {
                if NotchcastPreferences.shared.isEnabled(.spotifyConnect) { coordinator.refreshKey() }
            }
            .onChange(of: NotchcastPreferences.shared.isEnabled(.spotifyConnect)) { _, enabled in
                if enabled { coordinator.refreshKey() }
            }
        }
        .settingsEnabled(NotchcastPreferences.shared.isOn(.island)
            && NotchcastPreferences.shared.isOn(.musicNowPlaying))
    }
}

struct SpotifyDeviceNameSettingRow: View {
    @Environment(SpotifySettingsCoordinator.self) private var coordinator
    @FocusState private var editingName: Bool
    @State private var deviceName = ""
    private var module: SpotifyConnectModule { coordinator.module }

    var body: some View {
        Group {
            LabeledContent {
                TextField(String(localized: "Device name", table: "Notchcast"), text: $deviceName)
                    .labelsHidden()
                    .frame(width: NotchcastSettingsMetrics.deviceField)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .focused($editingName)
                    .onSubmit { applyDeviceName() }
                    .onChange(of: editingName) { _, editing in if !editing { applyDeviceName() } }
                    .accessibilityLabel(String(localized: "Device name", table: "Notchcast"))
            } label: {
                SettingsRowTitle(.notchcastSpotify, LocalizedStringResource("Device name", table: "Notchcast"))
                Text("How this Mac appears in Spotify.", tableName: "Notchcast")
            }
            .onAppear { deviceName = module.deviceName }
        }
        .settingsEnabled(NotchcastPreferences.shared.isOn(.island)
            && NotchcastPreferences.shared.isOn(.musicNowPlaying))
    }
    private func applyDeviceName() {
        module.setDeviceName(deviceName)
        deviceName = module.deviceName
    }
}

struct SpotifyBuildSettingRow: View {
    @Environment(SpotifySettingsCoordinator.self) private var coordinator

    var body: some View {
        Group {
            SpotifyBuildRow(module: coordinator.module, install: coordinator.installBuild)
        }
        .settingsEnabled(NotchcastPreferences.shared.isOn(.island)
            && NotchcastPreferences.shared.isOn(.musicNowPlaying))
    }
}

struct SpotifyTermsSettingRow: View {

    var body: some View {
        Group {
            Text(SpotifySettingsLinks.termsDescription)
        }
        .settingsEnabled(NotchcastPreferences.shared.isOn(.island)
            && NotchcastPreferences.shared.isOn(.musicNowPlaying))
    }
}

struct AudioPriorityOutputsSettingRow: View {
    @Bindable private var store = AudioPriorityPreferences.shared

    var body: some View {
        AudioPriorityDirectionRows(store: store, direction: .output)
    }
}

struct AudioPriorityMicrophonesSettingRow: View {
    @Bindable private var store = AudioPriorityPreferences.shared

    var body: some View {
        AudioPriorityDirectionRows(store: store, direction: .input)
    }
}

struct AudioPriorityFailureSettingRow: View {
    @Bindable private var store = AudioPriorityPreferences.shared

    var body: some View {
        if let failure = store.failure {
            Text(failure).foregroundStyle(.red)
        }
    }
}

private struct AudioPriorityDirectionRows: View {
    @Bindable var store: AudioPriorityPreferences
    let direction: AudioPriorityDevice.Direction

    var body: some View {
        if direction == .output {
            Toggle(String(localized: "Outputs", table: "Notchcast"), isOn: $store.outputsEnabled)
        } else {
            Toggle(String(localized: "Microphones", table: "Notchcast"), isOn: $store.microphonesEnabled)
        }
        ForEach(store.ranking(for: direction).uids, id: \.self) { uid in
            HStack {
                Text(verbatim: store.name(uid))
                if !store.devices.contains(where: { $0.uid == uid && $0.direction == direction }) {
                    Text("Disconnected", tableName: "Notchcast").foregroundStyle(.secondary)
                    Button(String(localized: "Forget", table: "Notchcast")) { store.forget(uid, direction: direction) }
                }
                Spacer()
                Button(String(localized: "Move up", table: "Notchcast"), systemImage: "arrow.up") {
                    store.move(uid, by: -1, direction: direction)
                }
                .disabled(store.ranking(for: direction).uids.first == uid)
                Button(String(localized: "Move down", table: "Notchcast"), systemImage: "arrow.down") {
                    store.move(uid, by: 1, direction: direction)
                }
                .disabled(store.ranking(for: direction).uids.last == uid)
            }
        }
    }
}

struct MicrophoneHotKeyFailureSettingRow: View {
    @Environment(MicrophoneMute.self) private var microphone

    var body: some View {
        Group {
            if microphone.hotKeyStatus != nil {
                Text("Allow Accessibility access to mute microphones with F5.", tableName: "Notchcast")
                    .foregroundStyle(Theme.Colors.destructive)
            }
        }
        .settingsEnabled(NotchcastPreferences.shared.isOn(.island))
    }
}

struct MicrophoneDeviceFailuresSettingRow: View {
    @Environment(MicrophoneMute.self) private var microphone

    var body: some View {
        ForEach(Array(microphone.failures.enumerated()), id: \.offset) { _, failure in
            LabeledContent {
                SymbolImage(name: "exclamationmark.circle.fill", size: Theme.Typography.menuSymbolSize)
                    .foregroundStyle(Theme.Colors.destructive)
                    .accessibilityHidden(true)
            } label: {
                Text(failure.device)
                Text(failure.message)
            }
            .accessibilityElement(children: .combine)
        }
        .settingsEnabled(NotchcastPreferences.shared.isOn(.island))
    }
}
