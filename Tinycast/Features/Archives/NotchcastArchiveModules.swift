extension NotchcastCore {
    static func archiveModuleEntries(_ module: ArchiveModule) -> [NotchcastModuleController.Entry] {
        [.init(requires: [.archives], module: module)]
    }
}
