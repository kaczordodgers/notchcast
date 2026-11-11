import SwiftUI

/// What the kernel builds on the music, microphone and task modules once they have registered.
@MainActor
final class NotchcastServices {
    let music: MusicNowPlayingModule
    let spotify: SpotifyConnectModule
    let microphone: MicrophoneMuteModule
    let marks: InUseMarksModule
    let settings: SpotifySettingsCoordinator
    let keys: NotchcastKeyMonitor
    private let commandFeedback: MusicCommandFeedback
    private let taskCommandAvailability: TodoCommandAvailability

    init?(core: AppCore, preferences: NotchcastPreferences) {
        guard let music = MusicNowPlayingModule.shared, let appleMusic = MusicBlockAppleMusicModule.shared,
              let spotify = SpotifyConnectModule.shared, let microphone = MicrophoneMuteModule.shared,
              let marks = InUseMarksModule.shared else { return nil }
        self.music = music
        self.spotify = spotify
        self.microphone = microphone
        self.marks = marks
        commandFeedback = MusicCommandFeedback(music: music, preferences: preferences)
        taskCommandAvailability = TodoCommandAvailability(preferences: preferences) { [weak core] in
            core?.appIndex.refreshNotchcastCommands()
        }
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
