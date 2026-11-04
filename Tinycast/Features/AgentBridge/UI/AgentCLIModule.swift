import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class AgentCLIModule: NotchcastModule {
    private(set) var isRunning = false
    private(set) var hasFailed = false
    let installer = AgentToolInstaller(
        source: Bundle.main.bundleURL.appending(path: "Contents/Helpers/notchcast"),
        directory: FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin"))
    @ObservationIgnored private var server: AgentSocketServer?

    func configure(index: AgentActionIndex) {
        guard server == nil else { return }
        let socketURL = AgentSocketClient.socketURL(
            home: FileManager.default.homeDirectoryForCurrentUser,
            bundleID: Bundle.main.bundleIdentifier ?? "app.notchcast.dev")
        server = AgentSocketServer(socketURL: socketURL) { [weak index] request in
            guard let index else { return .init(code: .notRunning) }
            return await index.handle(request)
        }
    }

    func start() {
        guard let server else { return }
        do {
            try server.start()
            isRunning = true
            hasFailed = false
        } catch {
            hasFailed = true
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.notchcast.dev", category: "AgentCLI")
                .error("Unable to start agent socket: \(error)")
        }
    }

    func stop() {
        server?.stop()
        isRunning = false
    }

    isolated deinit { server?.stop() }
}
