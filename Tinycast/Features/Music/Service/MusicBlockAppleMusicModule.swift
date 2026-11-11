@MainActor
final class MusicBlockAppleMusicModule: NotchcastModule {
    let blocker: MusicLaunchBlocker

    init(music: MusicNowPlayingModule) {
        blocker = MusicLaunchBlocker { [weak music] playing in
            if let music, music.soloist.isReady {
                if playing { music.soloist.send(.play) }
                return Task {}
            }
            return music?.model.openReplacement(startingPlayback: playing) ?? Task {}
        }
    }

    func start() { blocker.setEnabled(true) }
    func stop() { blocker.setEnabled(false) }
}
