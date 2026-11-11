import Foundation
import SQLite3

struct AgentThreadProject: Sendable, Equatable {
    let id: String
    let title: String
}

protocol AgentThreadProjectReading: Sendable {
    func projects() async throws -> [AgentThreadProject]
}

struct AgentThreadProjects: AgentThreadProjectReading {
    var url = AgentPaths(home: FileManager.default.homeDirectoryForCurrentUser).t3State

    @concurrent
    func projects() async throws -> [AgentThreadProject] {
        var database: OpaquePointer?
        let status = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        defer { sqlite3_close(database) }
        guard status == SQLITE_OK else { throw AgentThreadFailure.unavailable }
        sqlite3_busy_timeout(database, 500)
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let query = "SELECT project_id, title FROM projection_projects WHERE deleted_at IS NULL AND archived_at IS NULL"
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            throw AgentThreadFailure.commandFailed
        }
        var projects: [AgentThreadProject] = []
        while true {
            try Task.checkCancellation()
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let id = sqlite3_column_text(statement, 0),
                      let title = sqlite3_column_text(statement, 1) else { continue }
                projects.append(AgentThreadProject(id: String(cString: id), title: String(cString: title)))
            case SQLITE_DONE: return projects
            default: throw AgentThreadFailure.commandFailed
            }
        }
    }
}
