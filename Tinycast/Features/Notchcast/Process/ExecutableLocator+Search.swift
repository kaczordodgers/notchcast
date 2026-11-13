import Foundation

extension ExecutableLocator {
    nonisolated static func toolEnvironment(
        directories: [URL]? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        inherited: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        let folders = directories ?? searchDirectories(home: home, path: inherited["PATH"] ?? "/usr/bin:/bin")
        var environment = ["PATH": folders.map(\.path).joined(separator: ":"),
            "HOME": home.path, "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8"]
        for key in ["TMPDIR", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
                    "http_proxy", "https_proxy", "all_proxy", "no_proxy",
                    "SSL_CERT_FILE", "SSL_CERT_DIR", "USER", "LOGNAME"] {
            environment[key] = inherited[key]
        }
        return environment
    }

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
