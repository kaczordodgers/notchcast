import Foundation
import Observation

@Observable @MainActor
final class TorrentModule: NotchcastModule {
    private(set) var isRunning = false
    private(set) var toolURL: URL?
    private(set) var toolChecked = false
    let preferences: NotchcastPreferences
    @ObservationIgnored private let monitor: NetMergeInterfaceMonitor
    @ObservationIgnored private let readInterfaces: () throws -> [NetMergePolicy.Interface]
    @ObservationIgnored private let session: any TorrentSession
    @ObservationIgnored private let destination: URL
    @ObservationIgnored private let locator: any TorrentToolLocating
    @ObservationIgnored private var shutdown: Task<Void, Never>?
    @ObservationIgnored private var pending: [URL] = []
    @ObservationIgnored private(set) lazy var manager = TorrentManager(
        session: session, destination: destination,
        extraArguments: { [weak self] in self?.networkArguments() ?? ([], []) },
        interfacesPresent: { [weak self] names in self?.interfacesPresent(names) ?? false })

    init(
        session: any TorrentSession,
        preferences: NotchcastPreferences = .shared,
        destination: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads"),
        monitor: NetMergeInterfaceMonitor = NetMergeInterfaceMonitor(),
        locator: any TorrentToolLocating = TorrentToolLocator(),
        readInterfaces: (() throws -> [NetMergePolicy.Interface])? = nil
    ) {
        self.session = session
        self.preferences = preferences
        self.destination = destination
        self.monitor = monitor
        self.locator = locator
        self.readInterfaces = readInterfaces ?? monitor.readInterfaces
    }

    func start() { isRunning = true }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        pending.removeAll()
        guard shutdown == nil else { return }
        let manager = manager
        cancelAll()
        shutdown = Task { [weak self] in
            await manager.stop()
            guard let self else { return }
            self.shutdown = nil
            let waiting = self.pending
            self.pending.removeAll()
            for url in waiting { self.open(url) }
        }
    }

    @discardableResult func open(_ url: URL) -> Bool {
        guard isRunning, preferences.isOn(.torrents), Self.accepts(url) else { return false }
        if shutdown != nil {
            pending.append(url)
        } else {
            manager.enqueue([url], keepSharing: preferences.isOn(.torrentsKeepSharing))
        }
        return true
    }

    func cancelAll() {
        for job in manager.jobs where job.state.isRunning { manager.cancel(job.id) }
    }

    func tryAgain(_ id: UUID) {
        guard isRunning, preferences.isOn(.torrents), shutdown == nil else { return }
        manager.tryAgain(id)
    }

    func refreshTool() async {
        let url = await Self.findTool(locator)
        guard !Task.isCancelled else { return }
        toolURL = url
        toolChecked = true
    }

    static func accepts(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "magnet" || (url.isFileURL && url.pathExtension.lowercased() == "torrent")
    }

    private func networkArguments() -> (arguments: [String], interfaces: [String]) {
        guard preferences.isOn(.torrentsUseIPhone) else { return ([], []) }
        let interfaces = (try? readInterfaces()) ?? []
        let arguments = NetMergePolicy.evaluate(
            interfaces: interfaces, kind: .torrent, sizeBytes: nil, enabled: true).aria2Arguments
        return (arguments, NetMergePolicy.interfaceNames(in: arguments))
    }

    private func interfacesPresent(_ names: [String]) -> Bool {
        guard let interfaces = try? readInterfaces() else { return false }
        return names.allSatisfy { name in interfaces.contains { $0.bsdName == name && $0.hasIPv4 } }
    }

    @concurrent private static func findTool(_ locator: any TorrentToolLocating) async -> URL? {
        locator.aria2c()
    }
}
