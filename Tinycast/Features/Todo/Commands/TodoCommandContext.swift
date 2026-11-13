import Foundation

@MainActor
struct TodoCommandContext {
    var isEnabled: () -> Bool
    var store: () -> TodoStore?
    var clipboardText: () -> String?
    var report: (String) -> Void
    var now: () -> Date = { Date() }
    var calendar: Calendar = .current
    var language: TodoDateParser.Language = SystemLanguages.preferred.first
        .map { Locale(identifier: $0).language.languageCode?.identifier } == "pl" ? .polish : .english

    func add() {
        execute { store in
            guard let text = clipboardText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                report(String(localized: "The clipboard has no task text.", table: "Notchcast"))
                return
            }
            let instant = now()
            var parser = TodoQuickAddParser(text: text, projects: store.state.projects.values.map(\.name),
                sections: store.state.sections.values.map(\.name), labels: store.state.labels.values.map(\.name)) { text in
                guard let date = parseDate(text, now: instant) else { return nil }
                return TodoQuickAddDate(range: NSRange(date.matchedRange, in: text),
                                        display: date.normalised, payload: String(text[date.matchedRange]))
            }
            var draft = parser.draft
            let projectID = store.state.projects.values.sorted { $0.id < $1.id }
                .first { $0.name == draft.project }?.id
            let sectionID = store.state.sections.values.sorted { $0.id < $1.id }
                .first { $0.name == draft.section && $0.projectID == projectID }?.id
            while sectionID == nil, let token = draft.tokens.first(where: { $0.kind == .section }) {
                draft = parser.revert(tokenAt: token.range.location)
            }
            guard !draft.title.isEmpty else {
                report(String(localized: "The clipboard has no task text.", table: "Notchcast"))
                return
            }
            var task = TodoTask(id: UUID().uuidString, title: draft.title)
            task.priority = draft.priority
            task.addedAt = instant
            task.projectID = projectID
            task.sectionID = sectionID
            task.labels = draft.labels.compactMap { name in
                store.state.labels.values.sorted { $0.id < $1.id }.first { $0.name == name }?.id
            }
            if let payload = draft.date?.payload, let date = parseDate(payload, now: instant) {
                task.due = .init(date: date.date,
                                 time: date.time.map { DateComponents(hour: $0.hour, minute: $0.minute) },
                                 isAllDay: date.allDay, recurrenceRule: date.recurrence?.canonicalString,
                                 normalized: date.normalised)
            }
            try store.perform(.addTask(task))
            report(String(localized: "Task added from clipboard.", table: "Notchcast"))
        }
    }

    func complete() {
        execute { store in
            let instant = now()
            guard let task = TodoViews(state: store.state, now: instant, calendar: calendar)
                .today().first?.tasks.first?.task else {
                report(String(localized: "There are no tasks due today.", table: "Notchcast"))
                return
            }
            try store.perform(TodoCompletion.command(id: task.id, state: store.state, now: instant, calendar: calendar))
            report(String(localized: "Next task completed.", table: "Notchcast"))
        }
    }

    func undo() {
        execute { store in
            guard store.canUndo else {
                report(String(localized: "There is no task change to undo.", table: "Notchcast"))
                return
            }
            try store.undo()
            report(String(localized: "Last task change undone.", table: "Notchcast"))
        }
    }

    private func parseDate(_ text: String, now: Date) -> TodoDateParse? {
        TodoDateParser.parse(text, now: now, calendar: calendar, timeZone: calendar.timeZone,
                             preferredLanguage: language)
    }

    private func execute(_ action: (TodoStore) throws -> Void) {
        guard isEnabled() else { report(String(localized: "Tasks are turned off.", table: "Notchcast")); return }
        guard let store = store() else { report(String(localized: "The task store is unavailable.", table: "Notchcast")); return }
        do { try action(store) } catch { report(String(localized: "The task change could not be saved.", table: "Notchcast")) }
    }
}
