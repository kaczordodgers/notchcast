import Foundation

@MainActor
final class KatanaModule: NotchcastModule {
    let client = KatanaClient()
    let audio = KatanaAudioService()
    let tones = KatanaToneStore(file: URL.applicationSupportDirectory
        .appending(path: Bundle.main.bundleIdentifier ?? "app.notchcast.dev")
        .appending(path: "Katana/tones.json"))

    func start() {
        client.start()
        audio.start()
    }

    func stop() {
        client.stop()
        audio.stop()
    }
}
