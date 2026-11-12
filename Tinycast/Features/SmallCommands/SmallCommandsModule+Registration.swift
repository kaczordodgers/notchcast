extension SmallCommandsModule: NotchcastRegistrant {
    static let shared = SmallCommandsModule()

    static func register() -> [NotchcastModuleController.Entry] {
        [.init(requires: [.smallCommands], module: shared)]
    }
}
