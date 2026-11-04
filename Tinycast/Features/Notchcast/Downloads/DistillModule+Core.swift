import Foundation

extension DistillModule {
    convenience init(core: AppCore, services: NotchcastDownloadServices) {
        self.init(preferences: .shared, services: services,
                  file: AppPaths.applicationSupport().appending(path: "Notchcast/distill.json"),
                  linksFile: AppPaths.applicationSupport().appending(path: "Notchcast/distill-links.json"),
                  destination: NotchcastDownloadDestinations.distill,
                  report: { [weak core] in core?.showMessage($0, tone: .danger) })
        NotchcastDownloadLauncherCommands.distill = self
    }
}
