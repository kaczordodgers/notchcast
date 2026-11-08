import Foundation

extension DownloadsModule {
    convenience init(core: AppCore, services: NotchcastDownloadServices) {
        self.init(preferences: .shared, services: services,
                  file: NotchcastIdentity.supportRoot.appending(path: "Notchcast/downloads.json"),
                  destination: NotchcastDownloadDestinations.downloads,
                  report: { [weak core] in core?.showMessage($0, tone: .danger) })
        NotchcastDownloadLauncherCommands.downloads = self
        NotchcastDownloadLauncherCommands.trackAvailability(core)
    }
}
