import Foundation

@MainActor
final class WaitingAlertsModule: NotchcastModule {
    let alerts: WaitingAlerts

    init(source: any WaitingThreadSource,
         folder: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".t3/userdata"),
         post: @escaping @MainActor (String) -> Void) {
        alerts = WaitingAlerts(source: source, watcher: WaitingFolderMonitor(), folder: folder, post: post)
    }

    func start() { alerts.start() }
    func stop() { alerts.stop() }
}
