import SwiftUI

@MainActor
final class NotchcastServices {
    let music: MusicNowPlayingModule
    let lastPlayer: MusicLastPlayerModule
    let appleMusic: MusicBlockAppleMusicModule
    let spotify: SpotifyConnectModule
    let microphone: MicrophoneMuteModule
    let marks: InUseMarksModule
    let settings: SpotifySettingsCoordinator
    let keys: NotchcastKeyMonitor
    private let commandFeedback: MusicCommandFeedback

    init(core: AppCore, preferences: NotchcastPreferences) {
        let music = MusicNowPlayingModule(defaults: preferences.engineDefaults)
        self.music = music
        commandFeedback = MusicCommandFeedback(music: music, preferences: preferences)
        lastPlayer = MusicLastPlayerModule(model: music.model)
        appleMusic = MusicBlockAppleMusicModule(music: music)
        spotify = SpotifyConnectModule(source: music.soloist, defaults: preferences.engineDefaults)
        let mute = MicrophoneMute(audio: CoreMicrophoneAudio(), defaults: preferences.engineDefaults)
        microphone = MicrophoneMuteModule(model: mute, showMessage: { [weak core] in core?.showMessage($0) },
                                          showFailure: { [weak core] in core?.showMessage($0.message, tone: .danger) })
        marks = InUseMarksModule(model: InUseMarks(isMuted: { [weak mute] in mute?.isMuted == true }))
        settings = SpotifySettingsCoordinator(module: spotify, core: core)
        keys = NotchcastKeyMonitor(music: music, blocker: appleMusic.blocker, microphone: microphone,
                                    preferences: preferences, hub: NotchcastCore.eventTapHub)
    }
}

extension View {
    @ViewBuilder
    func notchcastEnvironment() -> some View {
        if let services = NotchcastCore.services {
            environment(services.music.model)
                .environment(services.music)
                .environment(services.spotify)
                .environment(services.microphone.model)
                .environment(services.microphone)
                .environment(services.marks.model)
                .environment(services.settings)
        } else {
            self
        }
    }
}
