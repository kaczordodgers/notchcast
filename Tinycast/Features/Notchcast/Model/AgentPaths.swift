import Foundation

/// Where the coding agents keep their state under a home folder.
nonisolated struct AgentPaths: Sendable {
    let home: URL

    var t3UserData: URL { home.appending(path: ".t3/userdata", directoryHint: .isDirectory) }
    var t3State: URL { t3UserData.appending(path: "statev2.sqlite", directoryHint: .notDirectory) }
    var t3Caches: URL { home.appending(path: ".t3/caches", directoryHint: .isDirectory) }
    var claudeProjects: [URL] { [".claude/projects", ".config/claude/projects"].map(folder) }
    var codexSessions: [URL] { [".codex/sessions", ".codex/archived_sessions"].map(folder) }

    private func folder(_ path: String) -> URL { home.appending(path: path, directoryHint: .notDirectory) }
}
