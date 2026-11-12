import Foundation

nonisolated struct ArchiveFallbackTools: Sendable {
    var paths: [String]

    init(environment: [String: String] = ProcessInfo.processInfo.environment,
         home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        paths = ExecutableLocator.searchDirectories(home: home, path: environment["PATH"] ?? "").map(\.path)
    }

    func require(_ name: String) throws -> URL {
        let directories = paths.map { URL(fileURLWithPath: $0) }
        guard let tool = ExecutableLocator.find(name, in: directories) else {
            throw ArchiveFailure.fallbackToolMissing(name == "zstd" ? "brew install zstd" : "brew install unar")
        }
        return tool
    }
}
