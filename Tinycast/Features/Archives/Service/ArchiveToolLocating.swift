import Foundation

nonisolated protocol ArchiveToolLocating: Sendable {
    func locate() -> URL?
}

nonisolated struct ArchiveToolLocator: ArchiveToolLocating {
    var environment = ProcessInfo.processInfo.environment
    var home = FileManager.default.homeDirectoryForCurrentUser
    var name = "hatchzip"

    func locate() -> URL? {
        ExecutableLocator.find(
            name, in: ExecutableLocator.searchDirectories(home: home, path: environment["PATH"] ?? ""))
    }
}
