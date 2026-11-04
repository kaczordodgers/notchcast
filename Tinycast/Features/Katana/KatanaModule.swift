import Foundation

@MainActor
final class KatanaModule: NotchcastModule {
    var commandTask: Task<Void, Never>?
    let client: KatanaClient
    let audio = KatanaAudioService()
    let tones = KatanaToneStore(file: URL.applicationSupportDirectory
        .appending(path: Bundle.main.bundleIdentifier ?? "app.notchcast.dev")
        .appending(path: "Katana/tones.json"))

    init(client: KatanaClient = KatanaClient()) {
        self.client = client
    }

    func start() {
        client.start()
        audio.start()
    }

    func stop() {
        commandTask?.cancel()
        client.stop()
        audio.stop()
    }
}
