import Foundation

@MainActor
final class DownloadsModule: NotchcastModule {
    var commandTask: Task<Void, Never>?
    let state: DownloadsQueueController
    private let preferences: NotchcastPreferences
    private let services: NotchcastDownloadServices

    var activity: DownloadsActivity { DownloadsActivity(jobs: state.queue?.jobs ?? []) }

    init(preferences: NotchcastPreferences, services: NotchcastDownloadServices,
         file: URL, destination: URL, report: @escaping (String) -> Void) {
        self.preferences = preferences
        self.services = services
        state = DownloadsQueueController(file: file, destination: destination, tools: services.tools,
                                         releaseSpeech: services.releaseSpeech, report: report)
    }

    func start() {
        state.start { [services, preferences] queue in
            for format in [MediaArguments.Format.video, .audio] {
                queue.register(NotchcastDownloadRunner(MediaDownloadRunner(format: format)) {
                    ["aria2Enabled": preferences.isOn(.downloadsAria2) ? "true" : "false"]
                })
            }
            queue.register(services.transcriptRunner)
            queue.register(WebpageRunner())
        }
    }

    func stop() {
        commandTask?.cancel()
        commandTask = nil
        state.stop()
    }
}
