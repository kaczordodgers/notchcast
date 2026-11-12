extension MusicNowPlayingModule: NotchcastRegistrant {
    static private(set) var shared: MusicNowPlayingModule?

    static func register() -> [NotchcastModuleController.Entry] {
        let defaults = NotchcastPreferences.shared.engineDefaults
        let music = MusicNowPlayingModule(defaults: defaults)
        let appleMusic = MusicBlockAppleMusicModule(music: music)
        let spotify = SpotifyConnectModule(source: music.soloist, defaults: defaults)
        shared = music
        MusicBlockAppleMusicModule.shared = appleMusic
        SpotifyConnectModule.shared = spotify
        return [
            .init(requires: [.island, .musicNowPlaying], module: music),
            .init(requires: [.island, .musicNowPlaying, .musicLastPlayer], module: MusicLastPlayerModule(model: music.model)),
            .init(requires: [.island, .musicBlockAppleMusic], module: appleMusic),
            .init(requires: [.island, .musicNowPlaying, .musicSharpCovers], module: MusicSharpCoversModule(model: music.model)),
            .init(requires: [.island, .musicNowPlaying, .spotifyConnect], module: spotify),
        ]
    }
}

extension MusicBlockAppleMusicModule {
    static fileprivate(set) var shared: MusicBlockAppleMusicModule?
}

extension SpotifyConnectModule {
    static fileprivate(set) var shared: SpotifyConnectModule?
}
