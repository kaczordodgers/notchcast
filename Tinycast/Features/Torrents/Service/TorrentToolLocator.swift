import Foundation

struct TorrentToolLocator: TorrentToolLocating {
    func aria2c() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        let directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init) + [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path,
            "/opt/homebrew/bin", "/usr/local/bin",
        ]
        return directories.lazy.filter { $0.hasPrefix("/") }.map {
            URL(fileURLWithPath: $0).appendingPathComponent("aria2c")
        }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
