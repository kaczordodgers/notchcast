extension MachineBackupCoordinator: NotchcastRegistrant {
    static let shared = MachineBackupCoordinator(tooling: MachineBackupRunner(), preferences: .shared)

    static func register() -> [NotchcastModuleController.Entry] {
        [.init(requires: [], requiresAny: [.backupRunNow, .backupBrowseRestore], module: shared)]
    }
}
