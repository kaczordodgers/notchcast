import Foundation

extension ExecutableLocator {
    /// Homebrew leads so a brewed tool beats the system's copy of the same name.
    nonisolated static func searchDirectories(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        path: String = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
    ) -> [URL] {
        let paths = ["/opt/homebrew/bin", "/usr/local/bin", home.appending(path: ".local/bin").path]
            + path.split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }.map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    /// Synchronous and shell-free: a polled caller cannot pay for `locate`'s login shell.
    nonisolated static func find(_ command: String, in directories: [URL] = searchDirectories()) -> URL? {
        guard !command.isEmpty, !command.contains("/"), command != ".", command != ".." else { return nil }
        return directories.lazy.map { $0.appending(path: command) }.first {
            var directory = ObjCBool(false)
            return FileManager.default.fileExists(atPath: $0.path, isDirectory: &directory)
                && !directory.boolValue && FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }
}
