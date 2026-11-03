import Foundation

extension DistillModule {
    convenience init(core: AppCore) {
        self.init(preferences: .shared, services: NotchcastDownloadServices(core: core),
                  file: AppPaths.applicationSupport().appending(path: "Notchcast/distill.json"),
                  linksFile: AppPaths.applicationSupport().appending(path: "Notchcast/distill-links.json"),
                  destination: FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads/Distill/Raw"),
                  report: { [weak core] in core?.showMessage($0, tone: .danger) })
    }
}
