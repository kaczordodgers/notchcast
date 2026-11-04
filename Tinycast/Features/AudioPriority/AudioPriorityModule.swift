import Foundation

@MainActor
final class AudioPriorityModule: NotchcastModule {
    let manager: AudioPriorityManager

    init(store: AudioPriorityPreferences = NotchcastPreferences.shared.audioPriority,
         transport: any AudioPriorityTransport = CoreAudioPriorityTransport()) {
        manager = AudioPriorityManager(transport: transport, store: store) { _ in
            store.failure = String(localized: "Could not change the audio device.")
        }
        manager.inventoryChanged = { store.update($0) }
        manager.succeeded = { store.failure = nil }
    }

    func start() { manager.start() }
    func stop() { manager.stop() }
}
