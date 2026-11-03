@MainActor
enum NotchcastCore {
    private static var controller: NotchcastModuleController?

    static func start(_ core: AppCore) {
        guard controller == nil else { return }
        IslandController.shared.configurePages(core)
        let modules: [NotchcastModuleController.Entry] = [
            .init(requires: [.island], module: IslandController.shared)
        ]
        let controller = NotchcastModuleController(modules, preferences: .shared)
        self.controller = controller
        controller.run()
    }
}
