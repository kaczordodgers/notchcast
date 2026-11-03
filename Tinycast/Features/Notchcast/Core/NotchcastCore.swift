@MainActor
enum NotchcastCore {
    private static var controller: NotchcastModuleController?
    static private(set) var services: NotchcastServices?

    static func start(_ core: AppCore, preferences: NotchcastPreferences = .shared) {
        guard controller == nil else { return }
        IslandController.shared.configurePages(core)
        let services = NotchcastServices(core: core, preferences: preferences)
        self.services = services
        let modules: [NotchcastModuleController.Entry] = [
            .init(requires: [.island], module: IslandController.shared),
            .init(requires: [.island, .musicNowPlaying], module: services.music),
            .init(requires: [.island, .musicNowPlaying, .musicLastPlayer], module: services.lastPlayer),
            .init(requires: [.island, .musicBlockAppleMusic], module: services.appleMusic),
            .init(requires: [.island, .musicNowPlaying, .spotifyConnect], module: services.spotify),
            .init(requires: [.island, .microphoneMute], module: services.microphone),
            .init(requires: [.island, .inUseMarks], module: services.marks)
        ]
        let controller = NotchcastModuleController(modules, preferences: preferences)
        self.controller = controller
        controller.run()
        services.keys.run()
    }
}
