import Foundation

extension DownloadsModule {
    convenience init(core: AppCore) {
        self.init(preferences: .shared, services: NotchcastDownloadServices(core: core),
                  file: AppPaths.applicationSupport().appending(path: "Notchcast/downloads.json"),
                  destination: FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads"),
                  report: { [weak core] in core?.showMessage($0, tone: .danger) })
    }
}
