import Observation

@MainActor
final class MusicCommandFeedback {
    private let music: MusicNowPlayingModule
    private let preferences: NotchcastPreferences
    private var availability: [Bool]?
    private var lastFailure: MusicModel.Failure?

    init(music: MusicNowPlayingModule, preferences: NotchcastPreferences) {
        self.music = music
        self.preferences = preferences
        observe()
    }

    private func observe() {
        withObservationTracking {
            let current = [preferences.isEnabled(.musicNowPlaying), preferences.isEnabled(.microphoneMute),
                           preferences.isEnabled(.musicLastPlayer), preferences.isEnabled(.spotifyConnect)]
            if availability != current { NotchcastHost.current.refreshNotchcastCommands() }
            availability = current
            let failure = music.model.failure
            if music.model.isEnabled, let failure, failure != lastFailure {
                switch failure {
                case .noReplacement, .launchFailed, .playbackFailed: MusicCommands.report()
                case .unreadable: break
                }
            }
            lastFailure = failure
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
    }
}
