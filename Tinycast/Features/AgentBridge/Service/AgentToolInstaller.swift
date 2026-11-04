import Foundation
import Observation

@MainActor
@Observable
final class AgentToolInstaller {
    enum State { case notInstalled, installed, failed }

    private(set) var state = State.notInstalled
    let source: URL
    let link: URL

    init(source: URL, directory: URL) {
        self.source = source
        link = directory.appending(path: "notchcast")
        refresh()
    }

    func refresh() {
        do {
            let target = try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
            state = target == source.path ? .installed : .notInstalled
        } catch {
            state = .notInstalled
        }
    }

    func install() {
        let files = FileManager.default
        guard files.isExecutableFile(atPath: source.path) else { state = .failed; return }
        do {
            try files.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let target = try? files.destinationOfSymbolicLink(atPath: link.path), target == source.path {
                state = .installed
                return
            }
            try files.createSymbolicLink(at: link, withDestinationURL: source)
            state = .installed
        } catch {
            state = .failed
        }
    }
}
