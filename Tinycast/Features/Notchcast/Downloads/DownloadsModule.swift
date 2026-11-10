import Foundation

@MainActor
final class DownloadsModule: NotchcastModule {
    let state: DownloadsQueueController
    private let preferences: NotchcastPreferences
    private let services: NotchcastDownloadServices
    private let readInterfaces: () throws -> [NetMergePolicy.Interface]

    var activity: DownloadsActivity { DownloadsActivity(jobs: state.queue?.jobs ?? []) }

    init(preferences: NotchcastPreferences, services: NotchcastDownloadServices,
         file: URL, destination: URL, report: @escaping (String) -> Void,
         readInterfaces: (() throws -> [NetMergePolicy.Interface])? = nil) {
        self.preferences = preferences
        self.services = services
        self.readInterfaces = readInterfaces ?? NetMergeInterfaceMonitor().readInterfaces
        state = DownloadsQueueController(
            file: file, destination: destination, speechKinds: [TranscriptDownloadRunner.kind],
            tools: services.tools, releaseSpeech: services.releaseSpeech, report: report)
        DownloadsIslandBridge.track(state)
    }

    func start() {
        state.start { [services, preferences, readInterfaces] queue in
            for format in [MediaArguments.Format.video, .audio] {
                queue.register(MediaDownloadRunner(format: format, aria2Enabled: {
                    preferences.isOn(.downloadsAria2)
                }, networkInterfaces: {
                    guard preferences.isOn(.torrentsUseIPhone) else { return [] }
                    return (try? readInterfaces()) ?? []
                }))
            }
            queue.register(services.transcriptRunner)
            queue.register(WebpageRunner())
        }
    }

    func stop() {
        state.stop()
    }
}
