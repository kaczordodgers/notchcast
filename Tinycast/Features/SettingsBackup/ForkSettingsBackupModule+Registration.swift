extension ForkSettingsBackupModule: NotchcastRegistrant {
    static let shared = ForkSettingsBackupModule()

    static func register() -> [NotchcastModuleController.Entry] {
        [.init(requires: [.settingsBackup], module: shared)]
    }
}

extension ForkSettingsBackupCoordinator {
    static let shared = ForkSettingsBackupCoordinator()
}
