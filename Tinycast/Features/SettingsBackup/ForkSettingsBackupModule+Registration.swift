extension ForkSettingsBackupModule: NotchcastRegistrant {
    static let shared = ForkSettingsBackupModule()

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [.init(requires: [.settingsBackup], module: shared)]
    }
}

extension ForkSettingsBackupCoordinator {
    static let shared = ForkSettingsBackupCoordinator()
}
