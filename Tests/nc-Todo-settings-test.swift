// notchcast-reads: Tests/Fixtures/todoist-export.json
// notchcast-sources: Tinycast/Features/Todo/Model/*.swift
// notchcast-sources: Tinycast/Features/Todo/Service/TodoStore*.swift
// notchcast-sources: Tinycast/Features/Todo/Service/TodoistImportClient.swift
// notchcast-sources: Tinycast/Features/Todo/Settings/TodoSettingsImport.swift
import Foundation

@main @MainActor
struct TodoSettingsTests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "export.json")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "Tests/Fixtures/todoist-export.json"), to: file)
        let store = try await TodoStore.open(directory: root.appending(path: "store"))
        let data = try await TodoistImportClient.export(from: FixtureExportSource(url: file))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar = Calendar(identifier: .gregorian)
        func apply(_ data: Data) throws -> Int {
            try TodoSettingsImport.apply(data, to: store, now: now,
                calendar: calendar, timeZone: calendar.timeZone)
        }
        let first = try apply(data)
        let second = try apply(data)
        precondition(first == 17 && second == 0)
        do {
            _ = try apply(Data("invalid".utf8))
            preconditionFailure("Invalid backup accepted")
        } catch {}
        precondition(store.state.tasks.count == 17)
        try store.close()
        let reopened = try await TodoStore.open(directory: root.appending(path: "store"))
        precondition(reopened.state.tasks.count == 17)
        try reopened.close()
        print("Todo settings: import, deduplication, invalid input and persistence passed")
    }
}
