import Foundation

@MainActor
final class AudioPriorityModule: NotchcastModule {
    let manager: AudioPriorityManager

    init() {
        let store = AudioPriorityPreferences.shared
        manager = AudioPriorityManager(transport: CoreAudioPriorityTransport(), store: store) { _ in
            store.failure = String(localized: "Could not change the audio device.", table: "Notchcast")
        }
        manager.inventoryChanged = { store.update($0) }
        manager.succeeded = { store.failure = nil }
    }

    func start() { manager.start() }
    func stop() { manager.stop() }
}
