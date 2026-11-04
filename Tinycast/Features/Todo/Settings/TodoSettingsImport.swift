import Foundation

enum TodoSettingsImport {
    @MainActor
    static func apply(_ data: Data, to store: TodoStore, now: Date,
                      calendar: Calendar, timeZone: TimeZone) throws -> Int {
        let report = try TodoistImportMapper.map(data, into: store.state, now: now,
            calendar: calendar, timeZone: timeZone, makeID: { UUID().uuidString })
        let before = store.state.tasks.count
        if !report.commands.isEmpty { try store.perform(.batch(report.commands)) }
        return store.state.tasks.count - before
    }
}
