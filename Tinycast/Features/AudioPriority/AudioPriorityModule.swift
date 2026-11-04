import Foundation

@MainActor
final class AudioPriorityModule: NotchcastModule {
    let manager: AudioPriorityManager

    init() {
        let store = NotchcastPreferences.shared.audioPriority
        manager = AudioPriorityManager(transport: CoreAudioPriorityTransport(), store: store) { error in
            store.failure = String(localized: "Could not change the audio device.")
        }
        manager.inventoryChanged = { store.update($0) }
    }

    func start() { manager.start() }
    func stop() { manager.stop() }
}
