@MainActor
enum NotchcastCore {
    private static var controller: NotchcastModuleController?

    static func start(_ core: AppCore) {
        guard controller == nil else { return }
        let modules: [NotchcastModuleController.Entry] = []
        let controller = NotchcastModuleController(modules)
        self.controller = controller
        let preferences = NotchcastPreferences.shared
        preferences.onChange = { [weak controller, weak preferences] _ in
            guard let preferences else { return }
            controller?.update(preferences)
        }
        controller.update(preferences)
    }
}
