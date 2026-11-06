import Foundation

nonisolated struct ArchiveFallbackTools: Sendable {
    var paths: [String]

    init(environment: [String: String] = ProcessInfo.processInfo.environment,
         home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        paths = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + [home.appending(path: ".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin"]
    }

    func require(_ name: String) throws -> URL {
        guard let tool = paths.filter({ $0.hasPrefix("/") })
            .map({ URL(fileURLWithPath: $0).appending(path: name) })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw ArchiveFailure.fallbackToolMissing(name == "zstd" ? "brew install zstd" : "brew install unar")
        }
        return tool
    }
}
