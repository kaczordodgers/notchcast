import Foundation

nonisolated protocol ArchiveToolLocating: Sendable {
    func locate() -> URL?
}

nonisolated struct ArchiveToolLocator: ArchiveToolLocating {
    var environment = ProcessInfo.processInfo.environment
    var home = FileManager.default.homeDirectoryForCurrentUser

    func locate() -> URL? {
        let paths = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + [home.appending(path: ".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin"]
        return paths.filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0).appending(path: "hatchzip") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
