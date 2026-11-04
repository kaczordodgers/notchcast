import Foundation
import Observation

@MainActor
@Observable
final class MusicNowPlayingModule: NotchcastModule {
    let model: MusicModel
    let soloist: SoloistSource
    private let system: SystemNowPlayingSource

    init(defaults: UserDefaults, apps: PlayerApps = .workspace()) {
        model = MusicModel(defaults: defaults, apps: apps)
        system = SystemNowPlayingSource()
        soloist = SoloistSource()
        model.setSystemSource(system)
        model.setSoloistSource(soloist)
        system.onCommandFailure = { [weak model] in model?.reportCommandFailure() }
    }

    func start() { model.setEnabled(true) }
    func stop() { model.setEnabled(false) }

    func send(_ command: PlayerCommand) {
        if model.isEnabled, model.nowPlaying == nil, soloist.isConnected,
            soloist.authState?.loggedIn == true, command == .play || command == .togglePlayPause {
            soloist.send(.play)
        } else {
            model.send(command)
        }
    }
}
