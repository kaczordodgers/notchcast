@MainActor
enum NotchcastCore {
    private static var controller: NotchcastModuleController?

    static func start(_ core: AppCore) {
        guard controller == nil else { return }
        let modules: [NotchcastModuleController.Entry] = [
            .init(requires: [.appearance], module: core.appearanceCoordinator)
        ]
        let controller = NotchcastModuleController(modules, preferences: .shared)
        self.controller = controller
        controller.run()
    }
}
