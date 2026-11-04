import Foundation

enum TodoCompletion {
    enum Failure: Error { case unsupportedRecurrence }

    static func command(id: String, state: TodoState, now: Date, calendar: Calendar) throws -> TodoCommand {
        guard var task = state.tasks[id], var due = task.due, let text = due.recurrenceRule else {
            return .completeTask(id: id, at: now)
        }
        guard let rule = TodoDateParser.parse(text, now: now, calendar: calendar,
                                             timeZone: calendar.timeZone, preferredLanguage: .english)?.recurrence else {
            throw Failure.unsupportedRecurrence
        }
        let anchored = rule.anchored(to: due.date, calendar: calendar)
        due.recurrenceRule = anchored.canonicalString
        due.date = TodoRecurrence.nextDue(anchored, currentDue: due.date, hasTime: !due.isAllDay,
                                         completedAt: now, calendar: calendar)
        task.due = due
        task.completedAt = nil
        var commands: [TodoCommand] = [.updateTask(task)]
        var parents: Set<String> = [id]
        while true {
            let children = state.tasks.values.filter { $0.parentID.map { parents.contains($0) } ?? false }
                .sorted { $0.id < $1.id }
            guard !children.isEmpty else { break }
            commands += children.map { .uncompleteTask(id: $0.id) }
            parents = Set(children.map(\.id))
        }
        return .batch(commands)
    }
}
