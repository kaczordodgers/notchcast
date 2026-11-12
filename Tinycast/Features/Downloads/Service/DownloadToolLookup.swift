import Foundation

struct DownloadToolLookup: Sendable {
    struct Reading: Sendable {
        let tool: DownloadTool
        let path: URL?
        let version: String?

        var status: String {
            path == nil ? String(localized: "Not installed") : String(localized: "Installed")
        }

        var installCommand: String { tool.installCommand }
    }

    let directories: [URL]
    private let inheritedEnvironment: [String: String]

    init(
        directories: [URL]? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment parent: [String: String] = ProcessInfo.processInfo.environment
    ) {
        let folders = directories
            ?? ExecutableLocator.searchDirectories(home: home, path: parent["PATH"] ?? "/usr/bin:/bin")
        self.directories = folders
        var environment = [
            "PATH": folders.map(\.path).joined(separator: ":"),
            "HOME": home.path
        ]
        for key in ["TMPDIR", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
                    "http_proxy", "https_proxy", "all_proxy", "no_proxy",
                    "SSL_CERT_FILE", "SSL_CERT_DIR", "USER", "LOGNAME"] {
            environment[key] = parent[key]
        }
        inheritedEnvironment = environment
    }

    func environment(running executable: URL) -> [String: String] {
        ExecutableLocator.environment(running: executable,
            adding: ["LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8"], inherited: inheritedEnvironment)
    }

    func find(_ tool: DownloadTool) -> URL? { ExecutableLocator.find(tool.name, in: directories) }

    @concurrent
    func lookup(_ tool: DownloadTool, timeout: Duration = .seconds(5)) async throws -> Reading {
        try Task.checkCancellation()
        guard let path = find(tool) else { return Reading(tool: tool, path: nil, version: nil) }
        let version = try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask {
                let result = try await ChildProcess(
                    executable: path, arguments: tool.versionArguments, environment: environment(running: path)).run()
                let output = result.output.isEmpty ? result.errors : result.output
                return output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            defer { group.cancelAll() }
            return try await group.next().flatMap { $0 }
        }
        try Task.checkCancellation()
        return Reading(tool: tool, path: path, version: version)
    }
}
