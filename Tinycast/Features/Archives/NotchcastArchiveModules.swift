extension NotchcastCore {
    static let archives = ArchiveModule(preferences: .shared)

    static func archiveModuleEntries(_ module: ArchiveModule) -> [NotchcastModuleController.Entry] {
        [.init(requires: [.archives], module: module)]
    }
}
