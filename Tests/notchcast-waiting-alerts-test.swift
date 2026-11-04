// notchcast-sources: Tinycast/Features/AgentFleet/AgentFleetExclusion.swift
// notchcast-sources: Tinycast/Features/AgentFleet/Waiting/WaitingThreadSource.swift
// notchcast-sources: Tinycast/Features/AgentFleet/Waiting/WaitingFolderWatching.swift
// notchcast-sources: Tinycast/Features/AgentFleet/Waiting/WaitingAlerts.swift
import Foundation

final class Source: WaitingThreadSource, @unchecked Sendable {
    // The harness mutates only between completed reads.
    var threads: [WaitingThread] = []
    var reads = 0
    func readWaitingThreads(in folder: URL) async throws -> [WaitingThread] {
        reads += 1
        return threads
    }
}

@MainActor
final class Watcher: WaitingFolderWatching {
    var callback: (@MainActor @Sendable () -> Void)?
    var stops = 0
    func start(folder: URL, changed: @escaping @MainActor @Sendable () -> Void) {
        callback = changed
    }
    func stop() { stops += 1 }
}

@main
struct Test {
    @MainActor
    static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = Source()
        let watcher = Watcher()
        var notices: [String] = []
        let wait = WaitingThread(id: "synthetic", title: "Test", kind: .approval)
        source.threads = [wait]
        let alerts = WaitingAlerts(source: source, watcher: watcher, folder: folder) { notices.append($0) }
        alerts.start()
        await alerts.settle()
        precondition(alerts.count == 1 && notices.isEmpty && source.reads == 1)
        watcher.callback?()
        await alerts.settle()
        precondition(source.reads == 2 && notices.isEmpty)
        source.threads = []
        watcher.callback?()
        await alerts.settle()
        precondition(alerts.count == 0)
        source.threads = [wait, wait]
        watcher.callback?()
        await alerts.settle()
        precondition(alerts.count == 1 && notices == ["Test"])
        watcher.callback?()
        await alerts.settle()
        precondition(notices.count == 1)
        source.threads = []
        watcher.callback?()
        await alerts.settle()
        source.threads = [wait]
        watcher.callback?()
        await alerts.settle()
        precondition(notices.count == 2)
        watcher.callback?()
        alerts.stop()
        await Task.yield()
        let reads = source.reads
        watcher.callback?()
        await Task.yield()
        precondition(alerts.count == 0 && source.reads == reads && watcher.stops == 1)
        for text in ["QUESTION: Why?", "BLOCKED: Missing input"] {
            precondition(WaitingThread.leadReport(id: "report", text: text) != nil)
        }
        for text in [" QUESTION: Why?", "QUESTIONING: Why?", "question: Why?", "BLOCKED:", "QUESTION: \n", "x BLOCKED: no"] {
            precondition(WaitingThread.leadReport(id: "report", text: text) == nil)
        }
        let excluded = WaitingAlerts(source: source, watcher: Watcher(),
            folder: folder.appending(path: AgentFleetExclusion.folderName)) { _ in preconditionFailure() }
        excluded.start()
        await excluded.settle()
        precondition(source.reads == reads)
        print("Waiting alerts passed")
    }
}
