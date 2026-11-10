import Foundation

extension DistillModule {
    convenience init(core: AppCore, services: NotchcastDownloadServices) {
        self.init(preferences: .shared, services: services,
                  file: NotchcastIdentity.supportRoot.appending(path: "Notchcast/distill.json"),
                  destination: NotchcastDownloadDestinations.distill,
                  report: { [weak core] in core?.showMessage($0, tone: .danger) })
        NotchcastDownloadLauncherCommands.distill = self
    }
}
