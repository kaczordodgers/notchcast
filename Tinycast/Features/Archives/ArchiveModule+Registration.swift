extension ArchiveModule: NotchcastRegistrant {
    static let shared = ArchiveModule(preferences: .shared)

    static func register() -> [NotchcastModuleController.Entry] {
        shared.queue.compressionFinished = { job in
            NotchcastHost.current.showMessage(job.failure?.message ?? job.stateTitle, job.failure == nil ? .neutral : .danger)
        }
        return [.init(requires: [.archives], module: shared)]
    }
}
