/// The music and microphone modules, each with the switches it runs under.
extension NotchcastServices {
    var moduleEntries: [NotchcastModuleController.Entry] {
        [
            .init(requires: [.island, .musicNowPlaying], module: music),
            .init(requires: [.island, .musicNowPlaying, .musicLastPlayer], module: lastPlayer),
            .init(requires: [.island, .musicBlockAppleMusic], module: appleMusic),
            .init(requires: [.island, .musicNowPlaying, .spotifyConnect], module: spotify),
            .init(requires: [.island, .microphoneMute], module: microphone),
            .init(requires: [.island, .inUseMarks], module: marks)
        ]
    }
}
