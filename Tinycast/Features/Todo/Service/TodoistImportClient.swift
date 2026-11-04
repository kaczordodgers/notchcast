import Foundation

protocol TodoistExportSource: Sendable {
    func export() async throws -> Data
}

struct FixtureExportSource: TodoistExportSource {
    let url: URL

    @concurrent func export() async throws -> Data {
        try Task.checkCancellation()
        return try Data(contentsOf: url)
    }
}

enum TodoistImportClient {
    static func export(from source: some TodoistExportSource) async throws -> Data {
        let data = try await source.export()
        try Task.checkCancellation()
        return data
    }
}
