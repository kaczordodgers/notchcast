import Observation

@MainActor
final class MusicCommandFeedback {
    private let music: MusicNowPlayingModule
    private let preferences: NotchcastPreferences
    private let blocker: MusicLaunchBlocker?
    private var availability: [Bool]?
    private var lastFailure: MusicModel.Failure?
    private var lastSoloistFailure: SoloistSource.Failure?
    private var lastBlockerFailure: MusicLaunchBlocker.Failure?

    init(music: MusicNowPlayingModule, preferences: NotchcastPreferences,
         blocker: MusicLaunchBlocker? = MusicBlockAppleMusicModule.shared?.blocker) {
        self.music = music
        self.preferences = preferences
        self.blocker = blocker
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
            let soloistFailure = music.soloist.failure
            if music.model.isEnabled, preferences.isEnabled(.spotifyConnect),
               let soloistFailure, soloistFailure != lastSoloistFailure {
                MusicCommands.report()
            }
            lastSoloistFailure = soloistFailure
            let blockerFailure = blocker?.failure
            if blocker?.isEnabled == true, let blockerFailure, blockerFailure != lastBlockerFailure {
                MusicCommands.report()
            }
            lastBlockerFailure = blockerFailure
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
    }
}
