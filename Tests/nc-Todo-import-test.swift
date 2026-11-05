// notchcast-sources: Tinycast/Features/Todo/Model/*.swift Tinycast/Features/Todo/Service/TodoistImportClient.swift
import Foundation

@main
struct TodoImportTests {
    static func main() async throws {
        let url = URL(fileURLWithPath: "Tests/Fixtures/todoist-export.json")
        let data = try await TodoistImportClient.export(from: FixtureExportSource(url: url))
        let zone = TimeZone(identifier: "Europe/Warsaw")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let now = ISO8601DateFormatter().date(from: "2026-11-04T12:00:00Z")!
        func map(_ state: TodoState, completed: Bool = false) throws -> TodoistImportMapper.ImportReport {
            try TodoistImportMapper.map(data, into: state, includeCompleted: completed,
                now: now, calendar: calendar, timeZone: zone, makeID: { UUID().uuidString })
        }
        let report = try map(TodoState())
        var state = TodoState()
        try state.apply(.batch(report.commands))
        precondition(state.tasks.count == 17 && state.projects.count == 1)
        precondition(state.sections.count == 1 && state.labels.count == 1)
        func task(_ ref: String) -> TodoTask {
            state.tasks.values.first { $0.externalRef == "todoist:sample-\(ref)" }!
        }
        precondition(task("one").priority == 4, "Todoist P1 must stay 4, never become P4")
        precondition(task("two").priority == 1 && task("three").priority == 2 && task("four").priority == 3)
        precondition(task("two").parentID == task("one").id)
        precondition(task("three").parentID == task("two").id)
        precondition(task("two").sectionID == task("one").sectionID)
        precondition(task("one").labels == Array(state.labels.keys))
        precondition(task("one").comments.first?.text == "A fictional comment.")
        precondition(task("fifteen").comments.first?.text == "A fictional note.")
        precondition(task("one").description == "Sample markdown" && task("one").order == 3)
        precondition(state.projects.values.first?.externalRef == "todoist:sample-project")
        precondition(task("four").due?.time?.hour == 9 && task("four").due?.isAllDay == false)
        precondition(task("eight").due?.isAllDay == true && task("eight").due?.time == nil)
        for name in ["four", "five", "six"] {
            precondition(task(name).due?.recurrenceRule != nil)
        }
        for (name, phrase) in [("four", "every monday at 9"), ("five", "every! 3 days"), ("six", "co tydzień")] {
            let parsed = TodoDateParser.parse(phrase, now: now, calendar: calendar,
                timeZone: zone, preferredLanguage: .english)
            precondition(task(name).due?.recurrenceRule == parsed?.recurrence?.canonicalString)
        }
        precondition(task("four").due?.date == ISO8601DateFormatter().date(from: "2026-11-09T08:00:00Z"))
        precondition(task("five").due?.recurrenceRule?.hasPrefix("every!") == true)
        precondition(task("six").title == "Zrobić przegląd")
        precondition(report.unparsedRecurrences == ["todoist:sample-seven"])
        precondition(task("seven").due?.normalized == "every blue moon")
        precondition(calendar.component(.day, from: task("seven").due!.date) == 12)
        for name in ["floating", "utc"] {
            precondition(task(name).due?.date == ISO8601DateFormatter().date(from: "2026-11-09T08:00:00Z"))
            precondition(task(name).due?.time?.hour == 9 && task(name).due?.isAllDay == false)
        }
        precondition(task("invalid").due == nil && report.unparsedDues == ["todoist:sample-invalid"])
        let repeated = try map(state)
        precondition(repeated.commands.isEmpty)
        let completed = try map(state, completed: true)
        try state.apply(.batch(completed.commands))
        precondition(state.tasks.count == 18 && task("nine").completedAt == now)
        let repeatedCompleted = try map(state, completed: true)
        precondition(repeatedCompleted.commands.isEmpty)
        let shared = Data(#"{"tasks":[{"id":"shared-a","content":"A","labels":["sample","shared"]},"#.utf8)
            + Data(#"{"id":"shared-b","content":"B","labels":["shared"]}]}"#.utf8)
        let sharedReport = try TodoistImportMapper.map(shared, into: state, now: now, calendar: calendar,
            timeZone: zone, makeID: { UUID().uuidString })
        try state.apply(.batch(sharedReport.commands))
        let sharedIDs = state.labels.values.filter { $0.name == "shared" }.map(\.id)
        precondition(state.labels.count == 2 && sharedIDs.count == 1, "A label missing from the export is created once")
        let sampleIDs = state.labels.values.filter { $0.name == "sample" }.map(\.id)
        precondition(state.tasks.values.first { $0.externalRef == "todoist:shared-a" }?.labels == sampleIDs + sharedIDs)
        precondition(state.tasks.values.first { $0.externalRef == "todoist:shared-b" }?.labels == sharedIDs)
        let invalid = Data("{\"tasks\":[{\"id\":\"fake\",\"content\":\"Invalid\",\"priority\":5}]}".utf8)
        do {
            _ = try TodoistImportMapper.map(invalid, into: state, now: now, calendar: calendar,
                timeZone: zone, makeID: { UUID().uuidString })
            preconditionFailure("Invalid priorities must reject the batch")
        } catch is TodoCommandError {}
        print("PASS Todoist import: counts, hierarchy, priority, labels, dates, recurrence, comments, idempotence")
    }
}
