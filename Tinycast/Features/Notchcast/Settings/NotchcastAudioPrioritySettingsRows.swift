import SwiftUI

struct NotchcastAudioPrioritySettingsRows: View {
    @Bindable private var preferences = NotchcastPreferences.shared

    var body: some View {
        Toggle("Audio device priority", isOn: $preferences.audioPriorityEnabled)
        if preferences.audioPriorityEnabled {
            DirectionRows(store: preferences.audioPriority, direction: .output)
            DirectionRows(store: preferences.audioPriority, direction: .input)
            if let failure = preferences.audioPriority.failure {
                Text(failure).foregroundStyle(.red)
            }
        }
    }

    private struct DirectionRows: View {
        @Bindable var store: AudioPriorityPreferences
        let direction: AudioPriorityDevice.Direction

        var body: some View {
            if direction == .output {
                Toggle("Outputs", isOn: $store.outputsEnabled)
            } else {
                Toggle("Microphones", isOn: $store.microphonesEnabled)
            }
            ForEach(store.ranking(for: direction).uids, id: \.self) { uid in
                HStack {
                    Text(verbatim: store.name(uid))
                    if !store.devices.contains(where: { $0.uid == uid && $0.direction == direction }) {
                        Text("Disconnected").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Move up", systemImage: "arrow.up") {
                        store.move(uid, by: -1, direction: direction)
                    }
                    .disabled(store.ranking(for: direction).uids.first == uid)
                    Button("Move down", systemImage: "arrow.down") {
                        store.move(uid, by: 1, direction: direction)
                    }
                    .disabled(store.ranking(for: direction).uids.last == uid)
                }
            }
        }
    }
}
