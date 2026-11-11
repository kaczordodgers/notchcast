extension MachineBackupCoordinator: NotchcastRegistrant {
    static let shared = MachineBackupCoordinator(tooling: MachineBackupRunner(), preferences: .shared)

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [.init(requires: [], requiresAny: [.backupRunNow, .backupBrowseRestore], module: shared)]
    }
}
